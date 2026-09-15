// A function that allocates, with the branch it takes when the allocator gives out reached by the
// failing allocator the run supplies on one call in four.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Copies the text, and says so when there was no room for it.
pub fn copyOrEmpty(log: Log, allocator: std.mem.Allocator, text: []const u8) []const u8 {
    const copied = allocator.dupe(u8, text) catch {
        if (an) annotate(log, "copyOrEmpty-no-room", "", .{});
        return "";
    };
    return copied;
}
