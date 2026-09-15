// Code driven by an exploration: every point the effect can fail at is found by running once with
// nothing failing, and then each one is failed in turn.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A store that can refuse a write. Its caller has to survive whichever way it refuses.
pub const Store = struct {
    ctx: *anyopaque,
    put: *const fn (ctx: *anyopaque, value: u8) anyerror!void,
};

// Writes every value, and stops at the first refusal rather than carrying on.
pub fn putAll(log: Log, store: Store, values: []const u8) usize {
    var written: usize = 0;
    for (values) |value| {
        if (an) annotate(log, "putAll-loop-iteration", "", .{});
        store.put(store.ctx, value) catch {
            if (an) annotate(log, "putAll-refused", "", .{});
            return written;
        };
        written += 1;
    }
    return written;
}
