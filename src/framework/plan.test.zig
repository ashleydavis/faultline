// Tests for the text a failure is reproduced from.

const std = @import("std");
const plan_mod = @import("plan.zig");
const Plan = plan_mod.Plan;
const Injection = plan_mod.Injection;
const Point = @import("point.zig").Point;

fn printed(allocator: std.mem.Allocator, plan: Plan) ![]u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    errdefer text.deinit();
    try plan.print(&text.writer);
    return text.toOwnedSlice();
}

test "a plan holding one injection round-trips through its own text" {
    const point: Point = .{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 0 };
    const injections = [_]Injection{.{ .point = point, .failure = "connection_refused" }};
    const original: Plan = .{ .injections = &injections };

    const text = try printed(std.testing.allocator, original);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("src/fetch.sim.zig:83#0=connection_refused", text);

    var parsed = try Plan.parse(std.testing.allocator, text);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expect(parsed.eql(original));
}

test "a plan carrying a seed round-trips too" {
    const original: Plan = .{ .injections = &.{}, .seed = 17 };

    const text = try printed(std.testing.allocator, original);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("seed=17", text);

    var parsed = try Plan.parse(std.testing.allocator, text);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expect(parsed.eql(original));
    try std.testing.expectEqual(@as(?u64, 17), parsed.seed);
}

test "a plan carrying a seed and an injection puts the seed first" {
    const point: Point = .{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 1 };
    const injections = [_]Injection{.{ .point = point, .failure = "timeout" }};
    const original: Plan = .{ .injections = &injections, .seed = 17 };

    const text = try printed(std.testing.allocator, original);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("seed=17,src/fetch.sim.zig:83#1=timeout", text);

    var parsed = try Plan.parse(std.testing.allocator, text);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expect(parsed.eql(original));
}

test "a plan holding several injections keeps them in order" {
    const injections = [_]Injection{
        .{ .point = .{ .file = "a.sim.zig", .line = 1, .occurrence = 0 }, .failure = "first" },
        .{ .point = .{ .file = "b.sim.zig", .line = 2, .occurrence = 0 }, .failure = "second" },
    };
    const original: Plan = .{ .injections = &injections };

    const text = try printed(std.testing.allocator, original);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("a.sim.zig:1#0=first,b.sim.zig:2#0=second", text);
}

test "failureFor answers only for a point the plan names" {
    const injections = [_]Injection{
        .{ .point = .{ .file = "a.sim.zig", .line = 1, .occurrence = 0 }, .failure = "refused" },
    };
    const plan: Plan = .{ .injections = &injections };

    try std.testing.expectEqualStrings("refused", plan.failureFor(.{ .file = "a.sim.zig", .line = 1, .occurrence = 0 }).?);
    try std.testing.expectEqual(@as(?[]const u8, null), plan.failureFor(.{ .file = "a.sim.zig", .line = 2, .occurrence = 0 }));
    try std.testing.expectEqual(@as(?[]const u8, null), plan.failureFor(.{ .file = "a.sim.zig", .line = 1, .occurrence = 1 }));
    try std.testing.expectEqual(@as(?[]const u8, null), plan.failureFor(.{ .file = "b.sim.zig", .line = 1, .occurrence = 0 }));
}

test "two plans differing in seed, length or an entry are not equal" {
    const one = [_]Injection{.{ .point = .{ .file = "a.sim.zig", .line = 1, .occurrence = 0 }, .failure = "refused" }};
    const other = [_]Injection{.{ .point = .{ .file = "a.sim.zig", .line = 1, .occurrence = 0 }, .failure = "timeout" }};

    try std.testing.expect(!(Plan{ .injections = &one }).eql(.{ .injections = &one, .seed = 1 }));
    try std.testing.expect(!(Plan{ .injections = &one }).eql(.{ .injections = &.{} }));
    try std.testing.expect(!(Plan{ .injections = &one }).eql(.{ .injections = &other }));
    try std.testing.expect((Plan{ .injections = &one }).eql(.{ .injections = &one }));
}

test "text that is not a plan is refused" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{
        "not a plan at all",
        "a.sim.zig:1#0",
        "a.sim.zig=refused",
        "a.sim.zig:notaline#0=refused",
        "a.sim.zig:1#notanoccurrence=refused",
        "seed=notanumber",
        "seed=1,seed=2",
    }) |text| {
        try std.testing.expectError(error.InvalidPlan, Plan.parse(allocator, text));
    }
}

test "a point only equals another naming the same place" {
    const point: Point = .{ .file = "a.sim.zig", .line = 1, .occurrence = 0 };
    try std.testing.expect(point.eql(.{ .file = "a.sim.zig", .line = 1, .occurrence = 0 }));
    try std.testing.expect(!point.eql(.{ .file = "b.sim.zig", .line = 1, .occurrence = 0 }));
    try std.testing.expect(!point.eql(.{ .file = "a.sim.zig", .line = 2, .occurrence = 0 }));
    try std.testing.expect(!point.eql(.{ .file = "a.sim.zig", .line = 1, .occurrence = 1 }));
}

test "an injection only equals another naming the same point and failure" {
    const injection: Injection = .{ .point = .{ .file = "a.sim.zig", .line = 1, .occurrence = 0 }, .failure = "refused" };
    try std.testing.expect(injection.eql(injection));
    try std.testing.expect(!injection.eql(.{ .point = injection.point, .failure = "timeout" }));
}
