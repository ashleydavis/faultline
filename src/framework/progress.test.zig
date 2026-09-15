// Tests for the record of what a function's calls have already reached.

const std = @import("std");
const Progress = @import("progress.zig").Progress;

test "the first call is always new" {
    var progress = Progress.init(std.testing.allocator);
    defer progress.deinit();

    try std.testing.expect(progress.observe(&.{ "entered", "took-the-branch" }));
}

test "the same call again is not new" {
    var progress = Progress.init(std.testing.allocator);
    defer progress.deinit();

    _ = progress.observe(&.{ "entered", "took-the-branch" });
    try std.testing.expect(!progress.observe(&.{ "entered", "took-the-branch" }));
}

test "a name that has not been annotated before is new" {
    var progress = Progress.init(std.testing.allocator);
    defer progress.deinit();

    _ = progress.observe(&.{"entered"});
    try std.testing.expect(progress.observe(&.{ "entered", "the-other-side" }));
}

test "a name annotated a different number of times is new" {
    var progress = Progress.init(std.testing.allocator);
    defer progress.deinit();

    // Once, then twice, then not at all: three different things a loop can do, and each of them is
    // a path the function had not taken before.
    try std.testing.expect(progress.observe(&.{ "entered", "iteration" }));
    try std.testing.expect(progress.observe(&.{ "entered", "iteration", "iteration" }));
    try std.testing.expect(progress.observe(&.{"entered"}));
    try std.testing.expect(!progress.observe(&.{ "entered", "iteration" }));
}

test "a call that annotated nothing is never new" {
    var progress = Progress.init(std.testing.allocator);
    defer progress.deinit();

    // There is nothing to have reached, so there is nothing this call can have reached first.
    try std.testing.expect(!progress.observe(&.{}));
    try std.testing.expect(!progress.observe(&.{}));
}

test "the names are copied, so what a call reported can die with it" {
    var progress = Progress.init(std.testing.allocator);
    defer progress.deinit();

    var name_buffer: [16]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "call-{d}", .{1});
    _ = progress.observe(&.{name});
    @memset(&name_buffer, 'x');

    const same = "call-1";
    try std.testing.expect(!progress.observe(&.{same}));
}
