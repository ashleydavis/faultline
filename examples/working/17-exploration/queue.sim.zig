// One exploration, and the factory the automatic driving uses for the same type.
//
// An exploration is found by its signature: an allocator and an injector. The run calls it once
// with an injector that records every point, then once more per point per way that point can fail,
// so every failing side is reached without a list of cases being written here.

const std = @import("std");
const sim = @import("sim");
const queue_mod = @import("queue.zig");

// The ways putting a value can fail. One `Failure` per field, derived from the enum that already
// names them, so the two can never drift apart.
const Fault = enum { full, read_only };
const put_failures = sim.failuresFrom(Fault, error.PutRefused);

// The store the exploration drives, which asks the injector whether this call should fail.
const Injected = struct {
    injector: *sim.Injector,

    fn put(ctx: *anyopaque, value: u8) anyerror!void {
        const self: *Injected = @ptrCast(@alignCast(ctx));
        _ = value;
        if (self.injector.check(@src(), 0, &put_failures)) |failure| {
            return failure.err;
        }
    }

    fn store(self: *Injected) queue_mod.Store {
        return .{ .ctx = self, .put = Injected.put };
    }
};

pub fn exploreEveryRefusal(allocator: std.mem.Allocator, injector: *sim.Injector) anyerror!void {
    _ = allocator;
    var injected = Injected{ .injector = injector };
    // No log is needed here: what the exploration proves is that the code survives every refusal,
    // and the coverage of its branches comes from the scenarios and the automatic driving.
    _ = queue_mod.putAll(.{}, injected.store(), &[_]u8{ 1, 2, 3 });
}

// The factory for `Store`, so the automatic driving can call every function that takes one and tick
// their branches.
pub const Fixed = struct {
    refuse: bool = false,

    fn put(ctx: *anyopaque, value: u8) anyerror!void {
        const self: *Fixed = @ptrCast(@alignCast(ctx));
        _ = value;
        if (self.refuse) {
            return error.PutRefused;
        }
    }
};

pub fn storeFrom(state: *Fixed) queue_mod.Store {
    return .{ .ctx = state, .put = Fixed.put };
}
