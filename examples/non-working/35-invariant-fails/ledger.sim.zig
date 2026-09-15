// An exploration and an invariant that does not hold after one of its injected runs.

const std = @import("std");
const sim = @import("sim");
const ledger_mod = @import("ledger.zig");

var under_test: ledger_mod.Ledger = .{};

const Fault = enum { rejected };
const write_failures = sim.failuresFrom(Fault, error.WriteRejected);

pub const invariants = [_]sim.Invariant{
    .{ .name = "the total never goes negative", .cost = .cheap, .ctx = &under_test, .check = totalStaysPositive },
};

fn totalStaysPositive(ctx: *anyopaque) anyerror!void {
    const ledger: *ledger_mod.Ledger = @ptrCast(@alignCast(ctx));
    if (ledger.total < 0) {
        return error.TotalWentNegative;
    }
}

pub fn exploreEveryRejection(allocator: std.mem.Allocator, injector: *sim.Injector) anyerror!void {
    _ = allocator;
    under_test = .{};
    // The credit is what keeps the total positive, so a run that fails this point and then takes
    // the amount anyway leaves the ledger negative.
    if (injector.check(@src(), 0, &write_failures) == null) {
        under_test.total += 10;
    }
    under_test.take(.{}, 5);
}
