// Tests for what a package registers as having to hold after every injected run.

const std = @import("std");
const invariant = @import("invariant.zig");

var counter: usize = 0;

fn alwaysHolds(ctx: *anyopaque) anyerror!void {
    const count: *usize = @ptrCast(@alignCast(ctx));
    count.* += 1;
}

fn neverHolds(_: *anyopaque) anyerror!void {
    return error.DidNotHold;
}

test "a cheap invariant and an expensive one are told apart by their cost" {
    const cheap: invariant.Invariant = .{ .name = "nothing leaked", .cost = .cheap, .ctx = &counter, .check = alwaysHolds };
    const expensive: invariant.Invariant = .{ .name = "the store is consistent", .cost = .expensive, .ctx = &counter, .check = alwaysHolds };

    try std.testing.expectEqual(invariant.Cost.cheap, cheap.cost);
    try std.testing.expectEqual(invariant.Cost.expensive, expensive.cost);
}

test "an invariant reads the state it was registered with" {
    counter = 0;
    const registered: invariant.Invariant = .{ .name = "counted", .cost = .cheap, .ctx = &counter, .check = alwaysHolds };

    try registered.check(registered.ctx);
    try registered.check(registered.ctx);

    try std.testing.expectEqual(@as(usize, 2), counter);
}

test "an invariant that does not hold hands its own error back" {
    const registered: invariant.Invariant = .{ .name = "never", .cost = .cheap, .ctx = &counter, .check = neverHolds };
    try std.testing.expectError(error.DidNotHold, registered.check(registered.ctx));
}

test "an invariant carries the name a violation is reported as" {
    const registered: invariant.Invariant = .{ .name = "the total never goes negative", .cost = .cheap, .ctx = &counter, .check = alwaysHolds };
    try std.testing.expectEqualStrings("the total never goes negative", registered.name);
}
