// A seed scenario that fails, so the run says which seed failed and how to reproduce it.

const std = @import("std");
const sim = @import("sim");
const draw_mod = @import("draw.zig");

pub const seeds = [_]u64{1};

pub fn runFailingSeedScenario(run: *sim.SeedRun) anyerror!void {
    // The bound is zero, so this can never come out true, which is the failure this example is for.
    if (!draw_mod.underBound(.{}, run.env.random(), 0)) {
        return error.DrewOutOfBound;
    }
}
