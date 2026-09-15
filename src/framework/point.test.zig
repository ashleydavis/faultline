// Tests for how a place a fault can be injected is named.

const std = @import("std");
const point_mod = @import("point.zig");
const Point = point_mod.Point;
const Failure = point_mod.Failure;

test "a point equals another naming the same place" {
    const point: Point = .{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 0 };
    try std.testing.expect(point.eql(.{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 0 }));
}

test "a point differing in file, line or occurrence is a different place" {
    const point: Point = .{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 0 };
    try std.testing.expect(!point.eql(.{ .file = "src/store.sim.zig", .line = 83, .occurrence = 0 }));
    try std.testing.expect(!point.eql(.{ .file = "src/fetch.sim.zig", .line = 84, .occurrence = 0 }));
    try std.testing.expect(!point.eql(.{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 1 }));
}

test "a point formats the way a plan and a reproduce command both read it" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.print("{f}", .{Point{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 2 }});
    try std.testing.expectEqualStrings("src/fetch.sim.zig:83#2", writer.buffered());
}

test "a point with no room to format into hands the error back" {
    var buffer: [4]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.WriteFailed,
        writer.print("{f}", .{Point{ .file = "src/fetch.sim.zig", .line = 83, .occurrence = 0 }}),
    );
}

test "a failure carries the name a plan types and the error the effect returns" {
    const failure: Failure = .{ .name = "connection_refused", .err = error.ConnectionRefused };
    try std.testing.expectEqualStrings("connection_refused", failure.name);
    try std.testing.expectEqual(@as(anyerror, error.ConnectionRefused), failure.err);
    // Most failures carry nothing beyond the error, which is what the default says.
    try std.testing.expectEqual(@as(?[]const u8, null), failure.data);
}

test "a failure can carry a value beyond its error" {
    const failure: Failure = .{ .name = "short_write", .err = error.WriteFailed, .data = "3" };
    try std.testing.expectEqualStrings("3", failure.data.?);
}
