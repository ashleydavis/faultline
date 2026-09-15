// Where a run's own report goes.
//
// One place, so it can be pointed somewhere other than the terminal. It goes to stderr for a real
// run, and nowhere in a test build: the framework's own tests drive failing runs on purpose to
// prove the reporting works, and each one prints a page of report. Left alone, `zig build test`
// buries its result under several of those and reads like a catastrophe when every test passed.
//
// A test that wants to read what was printed sets `writer` to one of its own and clears it after.

const std = @import("std");

// Whether this is a test binary. A run's report is for whoever ran it, and in a test build nobody
// asked for it.
const in_test = @import("builtin").is_test;

// Set to capture what a run prints. Null leaves it going wherever it goes by default.
pub var writer: ?*std.Io.Writer = null;

// The one place a run's report is written. Every line the framework prints goes through here.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    if (writer) |captured| {
        // A report that will not fit is not worth failing a run over: what is being reported is
        // already the problem.
        captured.print(fmt, args) catch {};
        return;
    }
    if (in_test) {
        return;
    }
    std.debug.print(fmt, args);
}
