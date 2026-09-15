const std = @import("std");
const auto = @import("auto.zig");

// A log standing in for a repository's own, which the framework never names. Nothing is written to
// it: what these tests are about is which arguments get built, not what the code under test does
// with them.
const FakeLog = struct {
    seen: usize = 0,
};

// A locator that can make nothing, for the cases about building a value out of its own type. The
// factory consults it first, so a test that wants the type walk has to say there is no other way.
const NoFactories = struct {
    pub fn canMake(comptime T: type) bool {
        _ = T;
        return false;
    }

    pub fn make(self: NoFactories, comptime T: type) T {
        _ = self;
        unreachable;
    }

    pub fn count(comptime T: type) usize {
        _ = T;
        return 0;
    }
};

const Context = auto.Context(FakeLog, NoFactories);

fn contextFor(arena: std.mem.Allocator, random: std.Random, recent: *auto.Recent, made: *usize, writer: *std.Io.Writer, trial: usize) Context {
    return .{
        .locator = .{},
        .arena = arena,
        .call_allocator = arena,
        .io = std.Io.failing,
        .log = .{},
        .random = random,
        .recent = recent,
        .literals = &.{},
        .writer = writer,
        .trial = trial,
        .made = made,
    };
}

const Made = struct {
    arena_state: std.heap.ArenaAllocator,
    prng: std.Random.Xoshiro256,
    recent: auto.Recent,
    made: usize,
    paper: [256]u8,
    writer: std.Io.Writer,
};

test "canMakeValue accepts the types a run can build and refuses the ones it cannot" {
    try std.testing.expect(comptime auto.canMakeValue(u32, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue(f64, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue(bool, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue([]const u8, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue(?u8, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue(FakeLog, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue(std.mem.Allocator, FakeLog, NoFactories));

    // An error is wanted as a whole argument, never as something built.
    try std.testing.expect(comptime auto.canMakeValue(anyerror, FakeLog, NoFactories));

    // A bare function pointer points nowhere useful, and an erased pointer has no type to build.
    try std.testing.expect(!(comptime auto.canMakeValue(*const fn () void, FakeLog, NoFactories)));
    try std.testing.expect(!(comptime auto.canMakeValue(*anyopaque, FakeLog, NoFactories)));
}

test "a tagged union is buildable when one of its variants is, and untagged never is" {
    const Mixed = union(enum) {
        ordinary: u32,
        opaque_pointer: *anyopaque,
    };
    try std.testing.expect(comptime auto.canMakeValue(Mixed, FakeLog, NoFactories));

    const Untagged = union {
        ordinary: u32,
    };
    try std.testing.expect(!(comptime auto.canMakeValue(Untagged, FakeLog, NoFactories)));
}

test "canExercise refuses a function taking something the run cannot build" {
    const Takes = struct {
        fn ordinary(value: u32, log: FakeLog) void {
            _ = value;
            _ = log;
        }

        fn erased(context: *anyopaque) void {
            _ = context;
        }
    };
    try std.testing.expect(comptime auto.canExercise(@TypeOf(Takes.ordinary), FakeLog, NoFactories));
    try std.testing.expect(!(comptime auto.canExercise(@TypeOf(Takes.erased), FakeLog, NoFactories)));
}

test "the trial budget grows with what a function's arguments can be" {
    const Narrow = struct {
        fn takesNothingInteresting(log: FakeLog) void {
            _ = log;
        }
    };
    const Wide = struct {
        const Deep = struct {
            first: ?[]const u8,
            second: ?[]const u8,
            third: ?u32,
        };

        fn takesDeep(value: Deep, log: FakeLog) void {
            _ = value;
            _ = log;
        }
    };

    const narrow = comptime auto.trialsFor(@TypeOf(Narrow.takesNothingInteresting), FakeLog, NoFactories);
    const wide = comptime auto.trialsFor(@TypeOf(Wide.takesDeep), FakeLog, NoFactories);

    try std.testing.expectEqual(auto.fewest_trials, narrow);
    try std.testing.expect(wide > narrow);
    try std.testing.expect(wide <= auto.most_trials);
}

test "an operation answers until its scripted failures run out" {
    var state: auto.OperationState = .{ .failures_left = 2 };
    const operation = auto.Operation(u32){ .state = &state };

    try std.testing.expectError(error.SimOperationFailed, operation.call({}, {}));
    try std.testing.expectError(error.SimOperationFailed, operation.call({}, {}));
    try std.testing.expectEqual(@as(u32, 0), try operation.call({}, {}));
    try std.testing.expectEqual(@as(usize, 3), state.calls);
}

test "a stand-in source yields what it was made with and then stops" {
    var items = auto.Items(u32){ .left = 2 };
    try std.testing.expect(items.next() != null);
    try std.testing.expect(items.next() != null);
    try std.testing.expect(items.next() == null);
}

test "the generic forms are told apart by what their parameters are" {
    const Forms = struct {
        fn withOperation(comptime Return: type, operation: anytype) anyerror!Return {
            return operation.call({}, {});
        }

        fn invoker(comptime FnT: type, comptime Return: type, args: anytype, function: anytype) anyerror!Return {
            const typed: FnT = function;
            return @call(.auto, typed, args);
        }

        // Counts as an invoker would, two types and two parameters with no type of their own, and
        // is not one: the last parameter's type is worked out from the two before it. Calling it
        // as an invoker puts a type where that context goes and the binary will not compile.
        fn heldContext(comptime function: anytype, comptime A: type, comptime B: type, held: Held(A, B)) void {
            _ = function;
            _ = held;
        }

        fn Held(comptime A: type, comptime B: type) type {
            return struct { first: A, second: B };
        }

        fn typeMaker(comptime Source: type, comptime Item: type) type {
            return struct {
                source: Source,
                held: ?Item = null,
            };
        }

        fn ordinary(value: u32) void {
            _ = value;
        }
    };

    try std.testing.expect(comptime auto.canExerciseGeneric(@TypeOf(Forms.withOperation)));
    try std.testing.expect(!(comptime auto.canExerciseGeneric(@TypeOf(Forms.ordinary))));

    try std.testing.expect(comptime auto.canExerciseInvoker(@TypeOf(Forms.invoker)));
    try std.testing.expect(!(comptime auto.canExerciseInvoker(@TypeOf(Forms.withOperation))));
    try std.testing.expect(!(comptime auto.canExerciseInvoker(@TypeOf(Forms.heldContext))));

    try std.testing.expect(comptime auto.canExerciseTypeMaker(@TypeOf(Forms.typeMaker)));
    try std.testing.expect(!(comptime auto.canExerciseTypeMaker(@TypeOf(Forms.invoker))));
}

test "building a value fills every field and reaches both sides of an optional" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var prng = std.Random.Xoshiro256.init(7);
    var recent: auto.Recent = .{};
    var paper: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&paper);

    const Pair = struct {
        left: u32,
        right: []const u8,
    };

    var saw_null = false;
    var saw_value = false;
    var trial: usize = 0;
    while (trial < 64) : (trial += 1) {
        var made: usize = 1;
        const ctx = contextFor(arena_state.allocator(), prng.random(), &recent, &made, &writer, trial);

        const pair = try auto.valueFactory(Pair, FakeLog, NoFactories, ctx);
        // Every field is filled: a string is one of the corpus entries, so its length is defined.
        _ = pair.left;
        _ = pair.right.len;

        const maybe = try auto.valueFactory(?u32, FakeLog, NoFactories, ctx);
        if (maybe == null) {
            saw_null = true;
        } else {
            saw_value = true;
        }
    }

    try std.testing.expect(saw_null);
    try std.testing.expect(saw_value);
}

test "an enum is built as one of its own values, and every one comes up" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var prng = std.Random.Xoshiro256.init(11);
    var recent: auto.Recent = .{};
    var paper: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&paper);

    const Side = enum { left, middle, right };
    var seen = [_]bool{false} ** 3;

    var trial: usize = 0;
    while (trial < 128) : (trial += 1) {
        var made: usize = 1;
        const ctx = contextFor(arena_state.allocator(), prng.random(), &recent, &made, &writer, trial);
        const side = try auto.valueFactory(Side, FakeLog, NoFactories, ctx);
        seen[@intFromEnum(side)] = true;
    }

    for (seen) |reached| {
        try std.testing.expect(reached);
    }
}

test "a slice the callee writes into is its own memory, never a corpus string" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    var prng = std.Random.Xoshiro256.init(3);
    var recent: auto.Recent = .{};
    var paper: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&paper);
    var made: usize = 1;

    const ctx = contextFor(arena_state.allocator(), prng.random(), &recent, &made, &writer, 5);

    var trial: usize = 0;
    while (trial < 32) : (trial += 1) {
        const room = try auto.valueFactory([]u8, FakeLog, NoFactories, ctx);
        // Writing through it is the whole point: a corpus string would fault here.
        for (room) |*byte| {
            byte.* = 1;
        }
    }
}

// A type holding a function pointer, which no signature decides a value for.
const Store = struct {
    ctx: *anyopaque,
    read: *const fn (ctx: *anyopaque) u8,
};

fn takesOrdinaryValues(log: FakeLog, count: usize, text: []const u8) usize {
    _ = log;
    _ = text;
    return count;
}

fn takesNoLog(count: usize) usize {
    return count;
}

fn takesAStore(log: FakeLog, store: Store) u8 {
    _ = log;
    return store.read(store.ctx);
}

fn takesAnything(log: FakeLog, value: anytype) usize {
    _ = log;
    _ = value;
    return 0;
}

fn takesLogByPointer(log: *const FakeLog) usize {
    _ = log;
    return 0;
}

test "a function whose every parameter can be built is exercised" {
    try std.testing.expect(comptime auto.canExercise(@TypeOf(takesOrdinaryValues), FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canExercise(@TypeOf(takesNoLog), FakeLog, NoFactories));
}

test "a generic function is not exercised from its signature, because nothing decides its types" {
    try std.testing.expect(!comptime auto.canExercise(@TypeOf(takesAnything), FakeLog, NoFactories));
}

test "a function taking a type nothing can build is not exercised" {
    try std.testing.expect(!comptime auto.canExercise(@TypeOf(takesAStore), FakeLog, NoFactories));
}

test "the parameter that stopped a function being exercised is named" {
    const stuck = comptime auto.firstUnbuildableParameter(@TypeOf(takesAStore), FakeLog, NoFactories).?;
    try std.testing.expectEqual(Store, stuck);
}

test "nothing is named for a function that can be exercised" {
    try std.testing.expectEqual(
        @as(?type, null),
        comptime auto.firstUnbuildableParameter(@TypeOf(takesOrdinaryValues), FakeLog, NoFactories),
    );
}

test "nothing is named for a generic function, whose problem is not a missing factory" {
    try std.testing.expectEqual(
        @as(?type, null),
        comptime auto.firstUnbuildableParameter(@TypeOf(takesAnything), FakeLog, NoFactories),
    );
}

test "a function is seen to take a log by value or by pointer" {
    try std.testing.expect(comptime auto.takesLog(@TypeOf(takesOrdinaryValues), FakeLog));
    try std.testing.expect(comptime auto.takesLog(@TypeOf(takesLogByPointer), FakeLog));
    try std.testing.expect(!comptime auto.takesLog(@TypeOf(takesNoLog), FakeLog));
}

test "a value that is not a function takes no log and stops nothing" {
    try std.testing.expect(!comptime auto.takesLog(usize, FakeLog));
    try std.testing.expect(!comptime auto.canExercise(usize, FakeLog, NoFactories));
    try std.testing.expectEqual(@as(?type, null), comptime auto.firstUnbuildableParameter(usize, FakeLog, NoFactories));
}

test "an ordinary type can be built and a function pointer cannot" {
    // Asked at compile time, because that is when the run asks it: whether a value can be made
    // decides whether the call is compiled in at all.
    try std.testing.expect(comptime auto.canMakeValue(usize, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue([]const u8, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue(?u8, FakeLog, NoFactories));
    try std.testing.expect(comptime auto.canMakeValue(FakeLog, FakeLog, NoFactories));
    try std.testing.expect(!comptime auto.canMakeValue(Store, FakeLog, NoFactories));
}

test "an error set can always be built, because one error is as good as another" {
    try std.testing.expect(comptime auto.canMakeValue(error{Broken}, FakeLog, NoFactories));
}

test "a parameter that takes an error is supplied directly rather than built" {
    try std.testing.expect(comptime auto.isSuppliedDirectly(anyerror));
    try std.testing.expect(!comptime auto.isSuppliedDirectly(usize));
}

test "the corpus for a type says how many different values the run sweeps through" {
    try std.testing.expect(comptime auto.corpusLength(usize) != 0);
    try std.testing.expect(comptime auto.corpusLength([]const u8) != 0);
    try std.testing.expect(comptime auto.corpusLength(bool) == 2);
}

test "how many calls a function gets is between the floor and the ceiling" {
    const trials = comptime auto.trialsFor(@TypeOf(takesOrdinaryValues), FakeLog, NoFactories);
    try std.testing.expect(trials >= auto.fewest_trials);
    try std.testing.expect(trials <= auto.most_trials);
}
