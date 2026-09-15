// Code a replay reproduces. The plan carries the seed as well as any injected faults, so one flag
// reproduces whatever the report printed.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Whether the draw came out inside the bound.
pub fn withinBound(log: Log, random: std.Random, bound: usize) bool {
    if (bound == 0) {
        if (an) annotate(log, "withinBound-no-room", "", .{});
        return false;
    } else {
        if (an) annotate(log, "withinBound-drew", "", .{});
    }
    return random.uintLessThan(usize, bound) < bound;
}
