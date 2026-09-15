// A seed scenario that fails, run again on its own through `--replay`.

const std = @import("std");
const sim = @import("sim");
const draw_mod = @import("draw.zig");

pub const seeds = [_]u64{1};

pub fn runFailingSeedScenario(run: *sim.SeedRun) anyerror!void {
    if (!draw_mod.underBound(.{}, run.env.random(), 0)) {
        return error.DrewOutOfBound;
    }
}
