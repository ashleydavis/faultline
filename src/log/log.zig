// The annotation channel: the whole of what a repository being fault tested depends on.
//
// A log type to take as a parameter, a compile-time flag, and one function to mark a branch with.
// Nothing that reads annotations back is here, because only the framework reads them, and a
// repository should not carry what it does not call.
//
// It imports nothing but `std` and the options module that says whether the trace points compile
// to anything at all.

const std = @import("std");

// The levels an entry can be recorded at. Only `.annotate` is produced by this file; the rest are
// here so a project putting its own logger behind `Log.write` has somewhere to put an ordinary log
// entry without inventing a second enum.
pub const Level = enum {
    err,
    warn,
    info,
    debug,
    verbose,
    event,
    tool,
    annotate,
};

// One key/value pair carried alongside a message, so a test can assert on structured detail
// without parsing a formatted string.
pub const Detail = struct {
    // What this piece of detail is, for example `"detail"`.
    key: []const u8,

    // The detail's own value.
    value: []const u8,
};

// Whatever is logging, addressed as one dispatch point and a context beside it. Zig has no
// closures: a function value cannot capture a mutable local, which the compiler refuses ("crosses
// namespace boundary"), so any pluggable single function needs a context beside it to carry state
// at all, the same way `std.mem.Allocator` and `std.Random` are already built. Two dispatch points
// rather than one, because an annotation is not a log entry: it is a trace point a run reads, it
// compiles out of a production build, and nothing routes it to output. Sending it through `write`
// made the log untraceable by itself, since the function doing the writing would have annotated
// through the writer it was implementing and never returned.
//
// Callers take `Log` by value, not a pointer to it, so a function that logs reads exactly like one
// that takes an allocator or an `io`.
pub const Log = struct {
    // The concrete logger's own state: `RecordingLog`'s entry list, or a project's own logger.
    ctx: *anyopaque = undefined,

    // Writes one entry. A project that does not log at all never calls this, and the default
    // throws the entry away.
    write: *const fn (ctx: *anyopaque, level: Level, message: []const u8, details: []const Detail) void = dropEntry,

    // Where annotations go, which is never the logger itself, for the reason above. The default
    // drops them, which is what a caller with nothing to record them in wants, and a production
    // build compiles every call out anyway.
    annotations: AnnotationWriter = .{},
};

// What `Log.write` defaults to: an entry nobody asked to keep goes nowhere.
fn dropEntry(_: *anyopaque, _: Level, _: []const u8, _: []const Detail) void {}

// Where a `Log` sends its annotations: one function and the state it writes into, the same pair
// `Log` itself is built from. Kept apart from `Log.write` so the log's own writing path can be
// annotated without calling itself.
pub const AnnotationWriter = struct {
    ctx: *anyopaque = undefined,
    record: *const fn (ctx: *anyopaque, name: []const u8, detail: []const u8) void = dropAnnotation,
};

// What an `AnnotationWriter` defaults to: an annotation nobody is recording goes nowhere.
fn dropAnnotation(_: *anyopaque, _: []const u8, _: []const u8) void {}

// Whether `annotate` below compiles to anything, read once from the options module the command
// generates for the repository it is fault testing: false in a production build, so it carries none of
// these, and true in a simulation run, which is the only build that reads them. A `pub const`
// rather than a function: it is already a comptime-known value, and every call site reads it
// directly in its own `if (an)` guard.
pub const an = @import("flt_options").annotations_enabled;

// How much room `annotate` formats a detail into. 256 bytes because a detail is a short piece of
// context beside a name (a count, an error name, a status), not a message, and a stack buffer this
// size costs nothing on a path that is already about to record an entry.
const detail_buffer_bytes = 256;

// Marks a point the code reached, for a run to tick a path off its checklist and for a test to
// assert on through `trace.zig`. Compiled out entirely when `an` is false. `name` is what a
// checklist matches on; `fmt`/`args` format additional detail alongside it, carried as one `Detail`
// rather than baked into `name` itself, so two calls with the same `name` and different detail
// still count as the same annotation.
//
// Guard every call with `if (an) annotate(...)` at the call site, never inside this function. `an`
// is a comptime-known bool, so a call sitting inside a dead `if (an)` branch is never compiled in
// at all, arguments included; a check inside `annotate` itself would still evaluate the caller's
// arguments (an `@errorName` call, a `results.len` read) before finding out they were not wanted.
//
// Not `inline`: its own fallback below names itself through this same function, which an inline
// function cannot do (the compiler expands the call forever). The `if (an)` guard at every call
// site is what keeps a production build from evaluating any of this, not the inlining.
pub fn annotate(log: Log, name: []const u8, comptime fmt: []const u8, args: anytype) void {
    // Its own trace points go straight to the sink rather than back through this function, which
    // would call itself for every annotation in the project.
    log.annotations.record(log.annotations.ctx, "annotate:entered", "");
    var buffer: [detail_buffer_bytes]u8 = undefined;
    const detail_value = std.fmt.bufPrint(&buffer, fmt, args) catch blk: {
        // One level deep and no further: this call formats an empty detail, which cannot overflow,
        // so it never reaches this branch itself.
        if (an) annotate(log, "annotate-detail-too-long", "", .{});
        break :blk name;
    };
    log.annotations.record(log.annotations.ctx, name, detail_value);
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("log.test.zig");
}
