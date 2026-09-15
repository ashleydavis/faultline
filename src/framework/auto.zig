// Drives a module's functions from their own types, with no scenario written for any of them. What
// a function takes is read off its signature at comptime and built here: the allocator, the `Io`
// and the log the run records through, plus values for the ordinary types (integers, floats,
// booleans, enums, optionals, slices, plain structs and pointers to them) drawn from a corpus of
// the values that make a branch go one way rather than the other.
//
// Nothing here names a package's own types. The log arrives as a type parameter, because what a log
// is belongs to the repository being simulated, and every other type is decided by `@typeInfo`.

const std = @import("std");

// The values a corpus offers for each ordinary type. Chosen for the branches they reach rather than
// for looking like real data: zero and one because a loop's zero, one and many split turns on them,
// the extremes because a range check has a side each, and the values around a boundary because that
// is where an off-by-one lives.
pub const integers = [_]i128{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 35, 36, 100, 255, 500, 1000, 1024, 1234, 1536, 65535, -1, -2, -100, 1 << 40, 1 << 51 };

// How much of the corpus above is the small end, drawn from far more often than the rest.
pub const small_integers = 13;
pub const floats = [_]f64{ 0, 1, -1, 0.5, 10, 90, 90.1, -90.1, 180, 180.1, -180.1, 1e300, std.math.nan(f64), std.math.inf(f64), -std.math.inf(f64) };
pub const strings = [_][]const u8{ "", "a", "0", "1", "-1", "1.5", "not a number", "OK", "n" ** 300 };

// The errors handed to a parameter that takes one. Which error it is almost never decides a branch,
// and where it does the code is comparing against its own, so this is a handful rather than a
// corpus: something to pass, and one that is out of memory because that one is handled everywhere.
pub const errors = [_]anyerror{ error.OutOfMemory, error.AccessDenied, error.Unexpected };

// How many values a corpus offers for a type, which is what the trial count is built from: one
// trial per combination up to the ceiling below.
pub fn corpusLength(comptime T: type) usize {
    return corpusLengthTo(T, value_depth_limit);
}

// A type that holds a pointer to itself has no bottom, so this counts only as far down as the
// factory itself builds.
fn corpusLengthTo(comptime T: type, comptime depth: usize) usize {
    if (depth == 0) {
        return 1;
    }
    return switch (@typeInfo(T)) {
        .int, .comptime_int => integers.len,
        .float, .comptime_float => floats.len,
        .bool => 2,
        .@"enum" => |info| info.fields.len,
        // Half the draws are null, so reaching anything inside takes twice as many as the inside
        // needs on its own. The same reasoning runs through the rest: this is how rare one
        // particular value is, not how many there are.
        .optional => |info| 2 * corpusLengthTo(info.child, depth - 1),
        .pointer => |info| if (info.size == .slice)
            (if (info.child == u8) strings.len else slice_lengths.len * corpusLengthTo(info.child, depth - 1))
        else
            corpusLengthTo(info.child, depth - 1),
        .@"struct" => |info| blk: {
            var total: usize = 1;
            for (info.fields) |field| {
                const length = corpusLengthTo(field.type, depth - 1);
                if (length > most_trials / total) {
                    break :blk most_trials;
                }
                total *= length;
            }
            break :blk total;
        },
        .@"union" => |info| blk: {
            var total: usize = 0;
            for (info.fields) |field| {
                total += corpusLengthTo(field.type, depth - 1);
            }
            break :blk if (total == 0) 1 else total;
        },
        .array => |info| info.len * corpusLengthTo(info.child, depth - 1),
        else => 1,
    };
}

// Whether every value of this type can be built here. A function taking one that cannot is left
// alone rather than called with something invented: a function pointer, an erased pointer or a
// type parameter has no value a signature alone decides.
// How far into a type this looks before giving up. A type holding a pointer to itself (an error
// with a cause, a node with a parent) has no bottom, so the walk needs an end that does not depend
// on the type having one.
pub const value_depth_limit = 12;

pub fn canMakeValue(comptime T: type, comptime Log: type, comptime ValueFactoryLocator: type) bool {
    return Answer(T, Log, ValueFactoryLocator).value;
}

// Zig instantiates a generic type once per set of arguments and keeps it, so a declaration inside
// one is computed once however often it is read. Without this the walk below runs again for every
// parameter of every function, and it recurses through every field of every type it meets.
fn Answer(comptime T: type, comptime Log: type, comptime ValueFactoryLocator: type) type {
    return struct {
        const value = answerFor(T, Log, ValueFactoryLocator);
    };
}

fn answerFor(comptime T: type, comptime Log: type, comptime ValueFactoryLocator: type) bool {
    if (@typeInfo(T) == .error_set) {
        return true;
    }
    return canMakeValueTo(T, Log, ValueFactoryLocator, value_depth_limit);
}

// The one error handed to a parameter that takes one. Which error it is almost never decides a
// branch, and where it does the code is comparing against its own.
pub const supplied_error = error.SimSuppliedError;

// Whether this argument is supplied directly rather than through the factory.
pub fn isSuppliedDirectly(comptime T: type) bool {
    return @typeInfo(T) == .error_set;
}

fn canMakeValueTo(comptime T: type, comptime Log: type, comptime ValueFactoryLocator: type, comptime depth: usize) bool {
    // A type nothing can be assembled out of can still be obtained by asking the code under test
    // for one: a value whose insides are function pointers is made by whatever makes it, and this
    // is how the run reaches functions taking one.
    if (ValueFactoryLocator.canMake(T)) {
        return true;
    }
    // The standard library's own interfaces, which every run already has a deterministic one of:
    // the allocator a call draws from, the `Io` it reads the clock and the network through, the
    // seeded random source, and the log it annotates through.
    if (T == Log or T == std.mem.Allocator or T == std.Io or T == std.Random or T == *std.Io.Writer) {
        return true;
    }
    if (depth == 0) {
        return false;
    }
    return switch (@typeInfo(T)) {
        .int, .comptime_int, .float, .comptime_float, .bool, .@"enum", .void => true,
        .error_set => true,
        .array => |info| canMakeValueTo(info.child, Log, ValueFactoryLocator, depth - 1),
        .optional => |info| canMakeValueTo(info.child, Log, ValueFactoryLocator, depth - 1),
        .pointer => |info| switch (info.size) {
            .slice => canMakeValueTo(info.child, Log, ValueFactoryLocator, depth - 1),
            .one => canMakeValueTo(info.child, Log, ValueFactoryLocator, depth - 1),
            else => false,
        },
        .@"struct" => |info| blk: {
            if (info.layout == .@"extern" or info.layout == .@"packed") break :blk false;
            for (info.fields) |field| {
                if (!canMakeValueTo(field.type, Log, ValueFactoryLocator, depth - 1)) break :blk false;
            }
            break :blk true;
        },
        // A tagged union is one of its variants, so one buildable variant is enough: the ones that
        // cannot be built are simply never chosen. An untagged union has no way to say which
        // variant a value is, so nothing can build one safely.
        .@"union" => |info| blk: {
            if (info.tag_type == null) break :blk false;
            for (info.fields) |field| {
                if (canMakeValueTo(field.type, Log, ValueFactoryLocator, depth - 1)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

// What a call under way is given: the arena every built value lives in, the allocator the code
// under test allocates from, the deterministic `Io` and clock it reads, the log it annotates
// through, and the seeded source every corpus choice is drawn from, so the whole sweep is one pure
// function of the seed it started from.
pub fn Context(comptime Log: type, comptime ValueFactoryLocator: type) type {
    return struct {
        const Self = @This();

        // What the context was built for, read back off the type so nothing has to be passed twice.
        pub const LogType = Log;
        pub const LocatorType = ValueFactoryLocator;

        // What can hand over a value of a type nothing can assemble.
        locator: ValueFactoryLocator,

        // Where values built for a call live. Reset between calls, so nothing a call built has to
        // be freed by hand and nothing survives into the next one.
        arena: std.mem.Allocator,

        // What the code under test allocates from, which is the arena as well: a function that
        // returns allocated memory is never asked to say who owns it, because the whole arena goes
        // at the end of the call.
        call_allocator: std.mem.Allocator,

        io: std.Io,
        log: Log,
        random: std.Random,

        // Which of this function's calls this is, and how many choices have already been made in
        // it. Together they turn the calls into a sweep rather than a sample: the first choice in
        // a call changes every time, the second every time the first has been all the way round,
        // and so on, so a parameter with eight values worth trying gets all eight rather than
        // whichever ones came up.
        trial: usize,
        made: *usize,

        // Somewhere for code that writes output to write it. A writer has to be a real one with
        // room behind it, so this is supplied like the allocator rather than built from its type.
        writer: *std.Io.Writer,

        // The strings the module being driven is written in terms of, which is where the exact
        // text a branch compares against comes from.
        literals: []const []const u8,

        // The strings already drawn for this call. A great many branches turn on one argument
        // matching something inside another (a name that is in the list, a type that is among the
        // types), and independent draws from a corpus almost never line up. Drawing a repeat of
        // something already used, some of the time, is what reaches those.
        recent: *Recent,

        // One corpus entry. Early choices in a call are swept, so every combination of the first
        // few is reached; once the sweep would need more calls than there are, the rest are drawn
        // from the seeded source instead, which is still the same every run.
        fn pick(self: Self, length: usize) usize {
            if (length <= 1) {
                return 0;
            }
            const stride = self.made.*;
            if (stride != 0 and stride <= self.trial) {
                self.made.* = stride * length;
                return (self.trial / stride) % length;
            }
            return self.random.uintLessThan(usize, length);
        }
    };
}

// The strings drawn so far in one call, kept so a later one can repeat an earlier one.
pub const Recent = struct {
    room: [8][]const u8 = undefined,
    used: usize = 0,

    fn remember(self: *Recent, value: []const u8) void {
        self.room[self.used % self.room.len] = value;
        self.used += 1;
    }

    fn any(self: *Recent, random: std.Random) ?[]const u8 {
        if (self.used == 0) {
            return null;
        }
        const held = @min(self.used, self.room.len);
        return self.room[random.uintLessThan(usize, held)];
    }
};

// Builds one value of `T` for a call. Every choice comes from the seeded source, so the same seed
// builds the same arguments and a failing call is reproduced by replaying that seed.
pub fn valueFactory(comptime T: type, comptime Log: type, comptime ValueFactoryLocator: type, ctx: Context(Log, ValueFactoryLocator)) error{OutOfMemory}!T {
    // The log is the run's own observation channel, so it is nearly always the recorder's. Now and
    // then it is one the code under test makes instead, which is the only way to reach a function
    // that is private to the implementation behind the interface: nothing can call it directly, and
    // the annotations it emits still arrive, because what it writes them to was wired here.
    if (T == Log) {
        if (comptime ValueFactoryLocator.canMake(Log)) {
            // Every so often the log is one the code under test makes rather than the recorder's.
            // That is the only way to reach an implementation's own private writing path: nothing
            // can call it directly, and what it annotates still arrives, because the sink it writes
            // to was located here and points at the recorder.
            if (ctx.pick(2) == 0) {
                return ctx.locator.make(Log, ctx.pick(comptime ValueFactoryLocator.count(Log)));
            }
        }
        return ctx.log;
    }
    if (comptime ValueFactoryLocator.canMake(T)) {
        return ctx.locator.make(T, ctx.pick(comptime ValueFactoryLocator.count(T)));
    }
    if (T == std.mem.Allocator) {
        return ctx.call_allocator;
    }
    if (T == std.Io) {
        return ctx.io;
    }
    if (T == std.Random) {
        if (comptime ValueFactoryLocator.canMake(std.Random)) {
            if (ctx.pick(2) == 0) {
                return ctx.locator.make(std.Random, ctx.pick(comptime ValueFactoryLocator.count(std.Random)));
            }
        }
        return ctx.random;
    }
    // Somewhere for code that writes output to write it. A writer has to be a real one with room
    // behind it, so it is supplied like the allocator rather than assembled from its type. Without
    // it nothing holding one can be made at all, and every implementation that writes is out of
    // reach.
    if (T == *std.Io.Writer) {
        return ctx.writer;
    }
    return switch (@typeInfo(T)) {
        .void => {},
        .bool => ctx.pick(2) == 1,
        .int => blk: {
            // Most draws come from the small end. A code comparing an orientation, an attempt
            // count or a stream index against 1, 2, 3 has a branch per value, and spreading draws
            // evenly across a corpus that also holds a petabyte reaches those a fraction of the
            // time. The large values stay for the clamping and overflow sides, drawn less often.
            const chosen = if (ctx.pick(4) != 0)
                integers[ctx.pick(small_integers)]
            else
                integers[ctx.pick(integers.len)];
            break :blk std.math.cast(T, chosen) orelse std.math.cast(T, @abs(chosen)) orelse 0;
        },
        .comptime_int => 0,
        .float => @floatCast(floats[ctx.pick(floats.len)]),
        .comptime_float => 0,
        .array => |info| blk: {
            var made: T = undefined;
            for (&made) |*slot| {
                if (comptime isSuppliedDirectly(info.child)) {
                    slot.* = supplied_error;
                } else {
                    slot.* = try valueFactory(info.child, Log, ValueFactoryLocator, ctx);
                }
            }
            break :blk made;
        },
        .@"enum" => |info| blk: {
            // The field values are comptime, so the choice is made over a comptime array of the
            // enum's own values rather than by indexing `info.fields` at runtime.
            const values = comptime made: {
                var each: [info.fields.len]T = undefined;
                for (info.fields, 0..) |field, index| {
                    each[index] = @enumFromInt(field.value);
                }
                break :made each;
            };
            if (values.len == 0) {
                break :blk undefined;
            }
            break :blk values[ctx.pick(values.len)];
        },
        .optional => |info| if (ctx.pick(2) == 0)
            null
        else if (comptime isSuppliedDirectly(info.child))
            supplied_error
        else
            try valueFactory(info.child, Log, ValueFactoryLocator, ctx),
        .pointer => |info| switch (info.size) {
            .slice => try sliceValue(T, info.child, info.is_const, Log, ValueFactoryLocator, ctx),
            .one => blk: {
                const room = try ctx.arena.create(info.child);
                if (comptime isSuppliedDirectly(info.child)) {
                    room.* = supplied_error;
                } else {
                    room.* = try valueFactory(info.child, Log, ValueFactoryLocator, ctx);
                }
                break :blk room;
            },
            else => @compileError("build: unsupported pointer"),
        },
        .@"struct" => |info| blk: {
            var made: T = undefined;
            inline for (info.fields) |field| {
                // A field with a default is usually left at it. A default is the value the type's
                // author says makes a whole one, and a list or a buffer built from independent
                // draws is not one: its length and the memory it points at would have nothing to
                // do with each other, and the first thing to read it would fault.
                // A field the locator can make is always made, never left at its default. Those
                // are the fields that decide where a value's output and annotations go, and their
                // default is "nowhere", which is exactly the value that makes the rest of the run
                // blind to whatever is built from it.
                const located = comptime ValueFactoryLocator.canMake(field.type);
                const default = comptime field.defaultValue();
                if (comptime isSuppliedDirectly(field.type)) {
                    @field(made, field.name) = supplied_error;
                } else if (!located and default != null and ctx.pick(4) != 0) {
                    @field(made, field.name) = default.?;
                } else {
                    @field(made, field.name) = try valueFactory(field.type, Log, ValueFactoryLocator, ctx);
                }
            }
            break :blk made;
        },
        // One variant of a tagged union, chosen from this call's own seeded source among the ones
        // that can be built, so every reachable variant comes up over enough calls.
        .@"union" => |info| blk: {
            const count = comptime made: {
                var total: usize = 0;
                for (info.fields) |field| {
                    if (canMakeValue(field.type, Log, ValueFactoryLocator)) total += 1;
                }
                break :made total;
            };
            const chosen = ctx.pick(count);
            var seen: usize = 0;
            inline for (info.fields) |field| {
                if (comptime canMakeValue(field.type, Log, ValueFactoryLocator)) {
                    if (seen == chosen) {
                        if (comptime isSuppliedDirectly(field.type)) {
                            break :blk @unionInit(T, field.name, supplied_error);
                        }
                        break :blk @unionInit(T, field.name, try valueFactory(field.type, Log, ValueFactoryLocator, ctx));
                    }
                    seen += 1;
                }
            }
            unreachable;
        },
        else => @compileError("build: unsupported type " ++ @typeName(T)),
    };
}

// The lengths a slice is built at: none, one, a few, and enough room for a caller that writes into
// it, which is the split a loop's zero, one and many paths turn on.
const slice_lengths = [_]usize{ 0, 1, 2, 3, 16, 64 };

// A slice of whatever the element type is: bytes come from the string corpus, since a string is
// where a parser's own branches are decided, and anything else is built element by element.
//
// A slice the callee can write into is always freshly allocated. A corpus string is a literal in
// read-only memory, so handing one to a function that writes through it would fault on the write
// rather than say anything about the code.
fn sliceValue(
    comptime T: type,
    comptime Child: type,
    comptime is_const: bool,
    comptime Log: type,
    comptime ValueFactoryLocator: type,
    ctx: Context(Log, ValueFactoryLocator),
) error{OutOfMemory}!T {
    if (Child == u8 and is_const) {
        const chosen = chosen: {
            // One draw in three repeats a string already used in this call, which is what reaches a
            // branch turning on two arguments being the same.
            if (ctx.pick(3) == 0) {
                if (ctx.recent.any(ctx.random)) |repeat| {
                    break :chosen repeat;
                }
            }
            // The module's own literals first, since those are the text its branches compare
            // against; the general corpus otherwise, for the empty, the long and the unparseable.
            const picked = if (ctx.literals.len > 0 and ctx.pick(4) != 0)
                ctx.literals[ctx.pick(ctx.literals.len)]
            else
                strings[ctx.pick(strings.len)];
            ctx.recent.remember(picked);
            break :chosen picked;
        };
        // A corpus string and a remembered one are both `[]const u8`, which is a different type
        // from `[:0]const u8`: the sentinel is part of the type, not a property of the bytes. A
        // parameter asking for one gets a copy that carries it.
        if (comptime sentinelOf(T, Child) == null) {
            return chosen;
        }
        const room = try roomFor(T, Child, ctx.arena, chosen.len);
        @memcpy(room, chosen);
        return room;
    }
    if (comptime isSuppliedDirectly(Child)) {
        const room = try roomFor(T, Child, ctx.arena, slice_lengths[ctx.pick(slice_lengths.len)]);
        for (room) |*slot| {
            slot.* = supplied_error;
        }
        return room;
    }
    if (Child == u8) {
        const room = try roomFor(T, u8, ctx.arena, slice_lengths[ctx.pick(slice_lengths.len)]);
        const filler = strings[ctx.pick(strings.len)];
        for (room, 0..) |*slot, index| {
            slot.* = if (filler.len == 0) 0 else filler[index % filler.len];
        }
        return room;
    }
    const room = try roomFor(T, Child, ctx.arena, slice_lengths[ctx.pick(slice_lengths.len)]);
    for (room) |*slot| {
        slot.* = try valueFactory(Child, Log, ValueFactoryLocator, ctx);
    }
    return room;
}

// The sentinel a slice type carries, or null where it carries none. `[:0]const u8` and
// `[]const u8` are two types, and a value of one does not pass where the other is asked for.
fn sentinelOf(comptime T: type, comptime Child: type) ?Child {
    return @typeInfo(T).pointer.sentinel();
}

// Room for a slice of `T`, allocated with T's own sentinel where it has one. What comes back is
// mutable, so the caller fills it and returns it: a mutable slice passes where a const one is
// asked for, and the sentinel rides along.
fn RoomFor(comptime T: type, comptime Child: type) type {
    if (comptime sentinelOf(T, Child)) |end| {
        return [:end]Child;
    }
    return []Child;
}

fn roomFor(
    comptime T: type,
    comptime Child: type,
    arena: std.mem.Allocator,
    length: usize,
) error{OutOfMemory}!RoomFor(T, Child) {
    if (comptime sentinelOf(T, Child)) |end| {
        return arena.allocSentinel(Child, length, end);
    }
    return arena.alloc(Child, length);
}

// How many times each function is called. Every argument is drawn afresh each time, so a branch
// needing one particular value out of the corpus is reached by trying often enough rather than by
// anybody saying which value it needs.
pub const trials_per_function = 400;

// The fewest and the most calls any one function gets. A function taking nothing but a log has one
// call worth making and the rest are waste; one taking a union of structs of slices has a space no
// number of calls covers, and the ceiling is what stops it taking the whole run.
pub const fewest_trials = 120;
pub const most_trials = 6000;

// How many times over the estimate each function is called.
pub const trials_over = 4;

// How many calls in a row may reach nothing new before a function's remaining calls are dropped.
//
// The trial count above is worked out from how rare a combination of arguments is, which says
// nothing about how many code paths a function has, so a function with a wide argument space is
// otherwise called thousands of times to reach a handful of paths and then thousands more to reach
// them again. What the run owes is every code path, not every combination of inputs.
//
// Set high enough that a path turning on something rare still comes up: the allocator fails one
// call in four and a call later each time, so this is hundreds of calls of allocation failures
// after the last new thing was seen, on top of everything the draws bring. Too low shows up at
// once, as a path nothing reached and a red run, rather than quietly.
pub const quiet_calls_before_stopping = 300;

// How many calls this function gets: as many as the values its own arguments can take, within those
// bounds. Spreading the same number over every function spends most of the run on the ones that
// needed a handful and starves the ones whose branches turn on a value that comes up rarely.
pub fn trialsFor(comptime Function: type, comptime Log: type, comptime ValueFactoryLocator: type) usize {
    comptime {
        var space: usize = 1;
        const info = @typeInfo(Function);
        if (info != .@"fn") {
            return fewest_trials;
        }
        for (info.@"fn".params) |param| {
            const T = param.type orelse continue;
            if (T == Log or T == std.mem.Allocator or T == std.Io or T == std.Random) {
                continue;
            }
            _ = ValueFactoryLocator;
            const length = corpusLength(T);
            if (length > most_trials / space) {
                return most_trials;
            }
            space *= length;
        }
        // The estimate is how many calls it takes to expect one of each value once, which is not
        // enough to expect a particular combination of several. A few times over is what turns
        // "should come up" into "does".
        if (space > most_trials / trials_over) {
            return most_trials;
        }
        const wanted = space * trials_over;
        if (wanted < fewest_trials) {
            return fewest_trials;
        }
        return wanted;
    }
}

// How many of a function's calls may crash before the rest of them are dropped. Every crash costs
// a restart and a restart replays the walk, so a function most of whose draws are outside what it
// accepts would otherwise cost more than the whole run to learn nothing new.
pub const crashes_before_dropping = 8;

// Whether a function can be called from its signature alone. A generic one cannot: `anytype` and a
// `comptime` type parameter have no value a signature decides, so something has to supply it and
// nothing here can.
pub fn canDrive(comptime Function: type, comptime Log: type, comptime ValueFactoryLocator: type) bool {
    const info = @typeInfo(Function);
    if (info != .@"fn") {
        return false;
    }
    if (info.@"fn".is_generic or info.@"fn".is_var_args) {
        return false;
    }
    inline for (info.@"fn".params) |param| {
        const T = param.type orelse return false;
        if (!canMakeValue(T, Log, ValueFactoryLocator)) {
            return false;
        }
    }
    return true;
}

// One call with one set of arguments. Split out so the arguments are built and the call made in one
// place whatever the function's arity is.
pub fn callOnce(comptime function: anytype, comptime Log: type, comptime ValueFactoryLocator: type, ctx: Context(Log, ValueFactoryLocator)) !void {
    const Function = @TypeOf(function);
    var args: std.meta.ArgsTuple(Function) = undefined;
    _ = &args;
    inline for (&args) |*slot| {
        if (comptime isSuppliedDirectly(@TypeOf(slot.*))) {
            slot.* = supplied_error;
        } else {
            slot.* = try valueFactory(@TypeOf(slot.*), Log, ValueFactoryLocator, ctx);
        }
    }

    // A function whose first argument is a pointer to something is often reading or releasing what
    // earlier calls on that same value did. Nothing it can be handed on its own has any of that in
    // it, so a few of its neighbours run against the same value first: a list that was written to
    // has entries to free, and a counter that was used has something to report.
    warmUp(Function, Log, ValueFactoryLocator, &args, ctx);

    const Return = @typeInfo(Function).@"fn".return_type.?;
    if (@typeInfo(Return) == .error_union) {
        _ = @call(.auto, function, args) catch {};
    } else {
        _ = @call(.auto, function, args);
    }
}

// How many of a value's other methods run against it before the one being fault tested.
pub const warm_up_calls = 3;

// Runs a few of the receiver's other methods against it, where there is a receiver to run them on.
fn warmUp(
    comptime Function: type,
    comptime Log: type,
    comptime ValueFactoryLocator: type,
    args: *std.meta.ArgsTuple(Function),
    ctx: Context(Log, ValueFactoryLocator),
) void {
    const params = @typeInfo(Function).@"fn".params;
    if (comptime params.len == 0) {
        return;
    }
    const First = comptime params[0].type orelse return;
    const pointer = comptime @typeInfo(First);
    if (comptime pointer != .pointer or pointer.pointer.size != .one) {
        return;
    }
    // A receiver the function only reads cannot be warmed up: the neighbours that would change it
    // take a pointer that can write, and handing them a `*const` one is the compiler's business to
    // refuse rather than something to cast away.
    if (comptime pointer.pointer.is_const) {
        return;
    }
    const Owner = comptime pointer.pointer.child;
    if (comptime @typeInfo(Owner) != .@"struct") {
        return;
    }

    var step: usize = 0;
    while (step < warm_up_calls) : (step += 1) {
        var seen: usize = 0;
        const chosen = ctx.pick(comptime neighbourCount(Owner, Function, Log, ValueFactoryLocator));
        inline for (@typeInfo(Owner).@"struct".decls) |decl| {
            const neighbour = @field(Owner, decl.name);
            if (comptime isNeighbour(Owner, @TypeOf(neighbour), Function, Log, ValueFactoryLocator)) {
                if (seen == chosen) {
                    callNeighbour(neighbour, Owner, Log, ValueFactoryLocator, args[0], ctx);
                }
                seen += 1;
            }
        }
    }
}

// How many other methods of `Owner` can be run against one of it, never counting the one being
// fault tested: running that first would fault test a call nothing set up.
fn neighbourCount(
    comptime Owner: type,
    comptime Function: type,
    comptime Log: type,
    comptime ValueFactoryLocator: type,
) usize {
    comptime {
        var total: usize = 0;
        for (@typeInfo(Owner).@"struct".decls) |decl| {
            if (isNeighbour(Owner, @TypeOf(@field(Owner, decl.name)), Function, Log, ValueFactoryLocator)) {
                total += 1;
            }
        }
        return if (total == 0) 1 else total;
    }
}

fn isNeighbour(
    comptime Owner: type,
    comptime Candidate: type,
    comptime Function: type,
    comptime Log: type,
    comptime ValueFactoryLocator: type,
) bool {
    if (Candidate == Function) {
        return false;
    }
    const info = @typeInfo(Candidate);
    if (info != .@"fn" or info.@"fn".is_generic or info.@"fn".is_var_args) {
        return false;
    }
    if (info.@"fn".params.len == 0 or info.@"fn".params[0].type != *Owner) {
        return false;
    }
    inline for (info.@"fn".params[1..]) |param| {
        const T = param.type orelse return false;
        if (!canMakeValue(T, Log, ValueFactoryLocator)) {
            return false;
        }
    }
    return true;
}

fn callNeighbour(
    comptime neighbour: anytype,
    comptime Owner: type,
    comptime Log: type,
    comptime ValueFactoryLocator: type,
    held: *Owner,
    ctx: Context(Log, ValueFactoryLocator),
) void {
    var args: std.meta.ArgsTuple(@TypeOf(neighbour)) = undefined;
    args[0] = held;
    inline for (&args, 0..) |*slot, index| {
        if (index == 0) {
            continue;
        }
        const T = @TypeOf(slot.*);
        if (comptime isSuppliedDirectly(T)) {
            slot.* = supplied_error;
        } else {
            slot.* = valueFactory(T, Log, ValueFactoryLocator, ctx) catch return;
        }
    }
    const result = @call(.auto, neighbour, args);
    if (comptime @typeInfo(@TypeOf(result)) == .error_union) {
        _ = result catch {};
    }
}

// What a run hands a parameter declared `anytype` where the function drives it as an operation:
// something to call that either answers or fails. This is the one protocol the framework knows,
// and it knows it because it is the only thing a signature leaves room for: a parameter with no
// type, driven by a function that calls a method on it.
//
// Which method, and with how many arguments, is read off the calling code rather than declared
// here: `call` taking whatever it is given is what every retrying and error-swallowing function in
// a repository built this way asks for, and a function asking for anything else is left alone
// rather than guessed at.
pub const OperationState = struct {
    // How many of the next calls fail before one succeeds, which is what reaches a retry loop's
    // "tried again" and "gave up" sides rather than only its first-time-lucky one.
    failures_left: usize = 0,

    // How many times it was called, so a run can see a loop went round.
    calls: usize = 0,
};

pub fn Operation(comptime Return: type) type {
    return struct {
        state: *OperationState,

        pub fn call(self: @This(), io: anytype, deadline: anytype) anyerror!Return {
            _ = io;
            _ = deadline;
            self.state.calls += 1;
            if (self.state.failures_left > 0) {
                self.state.failures_left -= 1;
                return error.SimOperationFailed;
            }
            return emptyValue(Return);
        }
    };
}

// The value an operation answers with when it succeeds. Nothing reads it: what the run is after is
// which way the calling code went, not what came back.
fn emptyValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .void => {},
        .int, .comptime_int => 0,
        .float, .comptime_float => 0,
        .bool => false,
        .optional => null,
        else => undefined,
    };
}

// The type handed to a `comptime T: type` parameter. Which type it is decides nothing about the
// paths a retrying function takes, so one stands for all of them.
pub const operation_return = u32;

// Whether a generic function is one this can drive: exactly one `comptime` parameter, which is a
// type, and at most one `anytype` beside it, which is then the operation. A function wanting a
// format string, a tuple of arguments to splice, or two different values a signature does not
// describe is left alone: passing an operation where one of those belongs would not compile, and
// there is no way to find that out except by trying.
pub fn canDriveGeneric(comptime Function: type) bool {
    const info = @typeInfo(Function);
    if (info != .@"fn" or !info.@"fn".is_generic or info.@"fn".is_var_args) {
        return false;
    }
    var types: usize = 0;
    var anys: usize = 0;
    for (info.@"fn".params) |param| {
        if (param.type) |declared| {
            if (declared == type) {
                types += 1;
            } else if (param.is_generic) {
                return false;
            }
        } else {
            anys += 1;
        }
    }
    return types == 1 and anys <= 1;
}

// Calls a generic function by assembling its arguments one at a time: an ordinary parameter is
// built from its own type as everywhere else, the `comptime` type parameter is given a type, and
// the `anytype` is given an operation. The tuple has to be put together rather than allocated,
// because a type is a comptime value and cannot be stored beside runtime ones any other way.
pub fn callGeneric(
    comptime function: anytype,
    comptime Log: type,
    comptime ValueFactoryLocator: type,
    comptime index: usize,
    args: anytype,
    ctx: Context(Log, ValueFactoryLocator),
    state: *OperationState,
) void {
    const params = @typeInfo(@TypeOf(function)).@"fn".params;
    if (comptime index == params.len) {
        // The return type only exists once the function is instantiated, which is what this call
        // does, so whether it returns an error is read off the result rather than off the signature.
        const result = @call(.auto, function, args);
        if (comptime @typeInfo(@TypeOf(result)) == .error_union) {
            _ = result catch {};
        }
        return;
    }

    const declared = comptime params[index].type;
    if (comptime declared == null) {
        callGeneric(function, Log, ValueFactoryLocator, index + 1, args ++ .{Operation(operation_return){ .state = state }}, ctx, state);
    } else if (comptime declared.? == type) {
        callGeneric(function, Log, ValueFactoryLocator, index + 1, args ++ .{operation_return}, ctx, state);
    } else if (comptime isSuppliedDirectly(declared.?)) {
        callGeneric(function, Log, ValueFactoryLocator, index + 1, args ++ .{supplied_error}, ctx, state);
    } else {
        const made = valueFactory(declared.?, Log, ValueFactoryLocator, ctx) catch return;
        callGeneric(function, Log, ValueFactoryLocator, index + 1, args ++ .{made}, ctx, state);
    }
}

// A call that takes another function to run, along with its type, what it returns and the arguments
// to give it. The run supplies all four: two stand-in functions, one that answers and one that
// fails, so both sides of whatever the caller does about a failure are reached.
//
// Which parameter is which is read off their kinds in order: the `comptime type` parameters are the
// function's own type and its return type, and the `anytype` parameters are its arguments and the
// function itself. A call whose parameters are in another order will not compile against this,
// which is the point at which somebody has to look rather than the run quietly driving nothing.
pub fn failingCall(io: std.Io) anyerror!operation_return {
    _ = io;
    return error.SimOperationFailed;
}

pub fn succeedingCall(io: std.Io) anyerror!operation_return {
    _ = io;
    return emptyValue(operation_return);
}

// Whether this is one of those. Two `comptime type` parameters and two `anytype` parameters, and
// nothing else the run cannot build.
//
// The two types come first, then the two `anytype`s, because that order is what tells an invoker
// from a function that merely counts the same. A parameter whose type is worked out from a comptime
// parameter before it reads as `anytype` here, since neither has a type a signature decides, so
// `fn (comptime function: anytype, comptime A: type, comptime B: type, ctx: Held(A, B))` counted
// as an invoker and was called with a type where its context goes. That is not a run that finds
// nothing: it is a compile error in the generated binary, which stops the whole repository being
// fault tested. This framework's own `callOnce` is that signature, found by fault testing it.
pub fn canDriveInvoker(comptime Function: type) bool {
    const info = @typeInfo(Function);
    if (info != .@"fn" or !info.@"fn".is_generic or info.@"fn".is_var_args) {
        return false;
    }
    var types: usize = 0;
    var anys: usize = 0;
    for (info.@"fn".params) |param| {
        if (param.type) |declared| {
            if (declared == type) {
                if (anys != 0) {
                    return false;
                }
                types += 1;
            } else if (param.is_generic) {
                return false;
            }
        } else {
            anys += 1;
        }
    }
    return types == 2 and anys == 2;
}

// Assembles the call: the stand-in's type, what it returns, an empty argument tuple and the
// stand-in itself, with everything else built from its own type as usual.
pub fn callInvoker(
    comptime function: anytype,
    comptime stub: anytype,
    comptime Log: type,
    comptime ValueFactoryLocator: type,
    comptime index: usize,
    comptime types_seen: usize,
    comptime anys_seen: usize,
    args: anytype,
    ctx: Context(Log, ValueFactoryLocator),
) void {
    const params = @typeInfo(@TypeOf(function)).@"fn".params;
    if (comptime index == params.len) {
        const result = @call(.auto, function, args);
        if (comptime @typeInfo(@TypeOf(result)) == .error_union) {
            _ = result catch {};
        }
        return;
    }

    const declared = comptime params[index].type;
    if (comptime declared == null) {
        if (comptime anys_seen == 0) {
            callInvoker(function, stub, Log, ValueFactoryLocator, index + 1, types_seen, 1, args ++ .{.{}}, ctx);
        } else {
            callInvoker(function, stub, Log, ValueFactoryLocator, index + 1, types_seen, 2, args ++ .{stub}, ctx);
        }
    } else if (comptime declared.? == type) {
        if (comptime types_seen == 0) {
            callInvoker(function, stub, Log, ValueFactoryLocator, index + 1, 1, anys_seen, args ++ .{@TypeOf(stub)}, ctx);
        } else {
            callInvoker(function, stub, Log, ValueFactoryLocator, index + 1, 2, anys_seen, args ++ .{operation_return}, ctx);
        }
    } else if (comptime isSuppliedDirectly(declared.?)) {
        callInvoker(function, stub, Log, ValueFactoryLocator, index + 1, types_seen, anys_seen, args ++ .{supplied_error}, ctx);
    } else {
        const made = valueFactory(declared.?, Log, ValueFactoryLocator, ctx) catch return;
        callInvoker(function, stub, Log, ValueFactoryLocator, index + 1, types_seen, anys_seen, args ++ .{made}, ctx);
    }
}

// A stand-in for something a caller reads items from one at a time, for driving a type that is
// built around a source. It yields as many as it was made with and then stops, which is what
// reaches the "ran out" side as well as the "kept going" one.
pub fn Items(comptime Item: type) type {
    return struct {
        left: usize = 0,

        pub fn next(self: *@This()) ?Item {
            if (self.left == 0) {
                return null;
            }
            self.left -= 1;
            return emptyValue(Item);
        }
    };
}

// Whether this is a function that makes a type out of two others: the thing it reads from and the
// thing it yields. The run instantiates it with a stand-in source and drives whatever comes back,
// which is the only way anything inside it is ever called.
//
// The order is read off their positions: what it reads from first, what it yields second. A maker
// whose parameters are the other way round will not compile against this, which is where somebody
// has to look rather than the run quietly driving nothing.
pub fn canDriveTypeMaker(comptime Function: type) bool {
    const info = @typeInfo(Function);
    if (info != .@"fn" or !info.@"fn".is_generic or info.@"fn".is_var_args) {
        return false;
    }
    const returns = info.@"fn".return_type orelse return false;
    if (returns != type) {
        return false;
    }
    if (info.@"fn".params.len != 2) {
        return false;
    }
    for (info.@"fn".params) |param| {
        const declared = param.type orelse return false;
        if (declared != type) {
            return false;
        }
    }
    return true;
}

// Which parameter stops a function being callable from its signature alone, named so a run can say
// what to write rather than leaving the function silently undriven. Null when every parameter can
// be built, and null for a generic function, whose problem is not a missing factory.
pub fn firstUnbuildableParameter(comptime Function: type, comptime Log: type, comptime ValueFactoryLocator: type) ?type {
    const info = @typeInfo(Function);
    if (info != .@"fn") {
        return null;
    }
    if (info.@"fn".is_generic or info.@"fn".is_var_args) {
        return null;
    }
    inline for (info.@"fn".params) |param| {
        const T = param.type orelse return null;
        if (!canMakeValue(T, Log, ValueFactoryLocator)) {
            return T;
        }
    }
    return null;
}

// Whether a function takes the log its branches would annotate through, by value or by pointer. A
// function that does not has nowhere to send an annotation, so none of its paths can ever be
// ticked however hard the run drives it.
pub fn takesLog(comptime Function: type, comptime Log: type) bool {
    const info = @typeInfo(Function);
    if (info != .@"fn") {
        return false;
    }
    inline for (info.@"fn".params) |param| {
        const T = param.type orelse continue;
        if (T == Log or T == *Log or T == *const Log) {
            return true;
        }
    }
    return false;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("auto.test.zig");
}
