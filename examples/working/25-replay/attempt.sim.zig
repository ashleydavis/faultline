// One seed scenario, which is what `--replay "seed=<n>"` runs again on its own.

const std = @import("std");
const sim = @import("sim");
const attempt_mod = @import("attempt.zig");

pub const seeds = [_]u64{ 1, 2, 3 };

pub fn runWithinBoundSeedScenario(run: *sim.SeedRun) anyerror!void {
    if (!attempt_mod.withinBound(.{}, run.env.random(), 10)) {
        return error.DrewOutOfBound;
    }
}
