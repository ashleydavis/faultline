// An exploration whose code crashes when the fault lands, so the harness prints the plan that
// reproduces it rather than the run simply dying.

const std = @import("std");
const sim = @import("sim");
const buffer_mod = @import("buffer.zig");

const Fault = enum { refused };
const fill_failures = sim.failuresFrom(Fault, error.FillRefused);

pub fn exploreEveryRefusal(allocator: std.mem.Allocator, injector: *sim.Injector) anyerror!void {
    _ = allocator;
    var values = [_]u8{ 1, 2, 3 };
    var filled: []const u8 = values[0..];
    if (injector.check(@src(), 0, &fill_failures)) |_| {
        // The fill was refused, so there is nothing in the list. The code under test reads the
        // first value anyway, which is the defect this example exists to show being caught.
        filled = values[0..0];
    }
    _ = buffer_mod.firstOf(filled);
}
