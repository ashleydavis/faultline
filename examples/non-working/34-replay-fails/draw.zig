const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Whether the draw came out under the bound. It does not, because the bound is zero.
pub fn underBound(log: Log, random: std.Random, bound: usize) bool {
    if (bound == 0) {
        if (an) annotate(log, "underBound-no-room", "", .{});
        return false;
    } else {
        if (an) annotate(log, "underBound-drew", "", .{});
    }
    return random.uintLessThan(usize, bound) < bound;
}
