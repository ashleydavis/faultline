// Code driven once per seed, against the world that seed built.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Picks a value within the bound, drawing from whatever random source it was handed.
pub fn boundedDraw(log: Log, random: std.Random, bound: usize) usize {
    if (bound == 0) {
        if (an) annotate(log, "boundedDraw-no-room", "", .{});
        return 0;
    } else {
        if (an) annotate(log, "boundedDraw-drew", "", .{});
    }
    return random.uintLessThan(usize, bound);
}
