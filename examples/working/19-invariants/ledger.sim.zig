// An exploration, and the two invariants that have to hold after every one of its runs.
//
// An invariant is registered by naming it in a `pub const invariants` beside the scenarios. A cheap
// one runs after every injected run; an expensive one is sampled, because a full consistency pass
// can cost more than the injection it is checking.

const std = @import("std");
const sim = @import("sim");
const ledger_mod = @import("ledger.zig");

// The ledger the exploration writes into, and what both invariants read.
var under_test: ledger_mod.Ledger = .{};

// The ways a write can fail.
const Fault = enum { rejected };
const write_failures = sim.failuresFrom(Fault, error.WriteRejected);

pub const invariants = [_]sim.Invariant{
    .{ .name = "entries never outnumber the total", .cost = .cheap, .ctx = &under_test, .check = entriesMatchTotal },
    .{ .name = "the total is never negative", .cost = .expensive, .ctx = &under_test, .check = totalStaysPositive },
};

fn entriesMatchTotal(ctx: *anyopaque) anyerror!void {
    const ledger: *ledger_mod.Ledger = @ptrCast(@alignCast(ctx));
    if (ledger.entries > ledger.total) {
        return error.MoreEntriesThanTotal;
    }
}

fn totalStaysPositive(ctx: *anyopaque) anyerror!void {
    const ledger: *ledger_mod.Ledger = @ptrCast(@alignCast(ctx));
    if (ledger.total < 0) {
        return error.TotalWentNegative;
    }
}

pub fn exploreEveryRejection(allocator: std.mem.Allocator, injector: *sim.Injector) anyerror!void {
    _ = allocator;
    under_test = .{};
    for ([_]i64{ 1, 2, 3 }) |amount| {
        if (injector.check(@src(), 0, &write_failures)) |_| {
            continue;
        }
        under_test.add(.{}, amount);
    }
}
