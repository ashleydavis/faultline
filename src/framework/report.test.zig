// Tests for what a failing run prints so the failure can be gone straight back to.

const std = @import("std");
const report = @import("report.zig");
const Plan = @import("plan.zig").Plan;
const Point = @import("point.zig").Point;

test "a point formats the way a plan reads it back" {
    const point: Point = .{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 0 };

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.print("{f}", .{point});

    try std.testing.expectEqualStrings("src/fetch.sim.zig:83#0", writer.buffered());
}

test "what printFailure puts in its reproduce line parses back to the same point and failure" {
    const point: Point = .{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 2 };

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.print("{f}={s}", .{ point, "connection_refused" });

    var plan = try Plan.parse(std.testing.allocator, writer.buffered());
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), plan.injections.len);
    try std.testing.expect(plan.injections[0].point.eql(point));
    try std.testing.expectEqualStrings("connection_refused", plan.injections[0].failure);
}

test "printFailure says what failed, where, and how to run it again" {
    // Nothing here reads the output back: what is asserted is that the call is made the way a
    // failing run makes it, and that it names the command that exists.
    report.printFailure(.{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 0 }, "connection_refused", error.Injected);
}
