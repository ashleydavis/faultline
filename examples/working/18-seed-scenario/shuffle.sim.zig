// A seed scenario, and this package's own seeds rather than the shared sweep.
//
// A seed scenario is found by its signature: the run that seed built. It is called once per seed,
// so a package with a case per seed writes one scenario rather than one per case.

const std = @import("std");
const sim = @import("sim");
const shuffle_mod = @import("shuffle.zig");

// The seeds this package sweeps. Named here rather than taking the shared sweep, because three
// runs are enough to show the scenario is called once per seed and the output stays readable.
pub const seeds = [_]u64{ 1, 2, 3 };

pub fn runBoundedDrawSeedScenario(run: *sim.SeedRun) anyerror!void {
    // The draw comes from the world this seed built, so the same seed draws the same value and a
    // failure is reproduced by naming the seed alone.
    const drawn = shuffle_mod.boundedDraw(.{}, run.env.random(), 10);
    if (drawn >= 10) {
        return error.DrewOutOfRange;
    }
}
