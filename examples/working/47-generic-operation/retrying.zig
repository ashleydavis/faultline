// A generic function the run calls without being told how: one `comptime` type parameter and one
// `anytype` beside it, which the run reads as something to call that either answers or fails.
//
// It supplies both, and varies how many calls fail first, so the trying again and the giving up
// sides are reached without a scenario being written for either.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Calls the operation until it answers or the attempts run out.
pub fn withRetries(log: Log, io: std.Io, comptime T: type, operation: anytype, attempts: usize) ?T {
    var attempt: usize = 0;
    while (attempt < attempts) : (attempt += 1) {
        if (an) annotate(log, "withRetries-attempting", "", .{});
        const answer = operation.call(io, attempt) catch {
            if (an) annotate(log, "withRetries-that-one-failed", "", .{});
            continue;
        };
        return answer;
    }
    if (an) annotate(log, "withRetries-gave-up", "", .{});
    return null;
}
