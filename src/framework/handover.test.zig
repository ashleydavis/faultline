const std = @import("std");
const handover = @import("handover.zig");

// Where these tests write. Under the repository's own tmp directory, which is ignored, the same
// place the other suites keep their fixtures.
const scratch = "tmp/handover-fixtures";

test "a handover round-trips its annotations, timings and counts" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const annotations = [_]handover.Annotation{
        .{ .module = "src/a.zig", .name = "a:entered", .from_runner = true },
        .{ .module = "src/b.zig", .name = "b-took-the-left", .from_runner = false },
    };
    const timings = [_]handover.Timing{
        .{ .file = "src/a.zig", .function = "first", .nanos = 1234, .calls = 56 },
    };
    const counts: handover.Counts = .{ .faults_injected = 3, .stepped_over = 4, .stalled = 1 };

    const path = scratch ++ "/round-1/handover.txt";
    try handover.writeHandover(allocator, io, path, &annotations, &timings, counts);

    var read = try handover.readHandover(allocator, io, path);
    defer read.deinit();

    try std.testing.expectEqual(@as(usize, 2), read.annotations.len);
    try std.testing.expectEqualStrings("src/a.zig", read.annotations[0].module);
    try std.testing.expectEqualStrings("a:entered", read.annotations[0].name);
    try std.testing.expect(read.annotations[0].from_runner);
    try std.testing.expectEqualStrings("b-took-the-left", read.annotations[1].name);
    try std.testing.expect(!read.annotations[1].from_runner);

    try std.testing.expectEqual(@as(usize, 1), read.timings.len);
    try std.testing.expectEqualStrings("first", read.timings[0].function);
    try std.testing.expectEqual(@as(u64, 1234), read.timings[0].nanos);
    try std.testing.expectEqual(@as(usize, 56), read.timings[0].calls);

    try std.testing.expectEqual(@as(usize, 3), read.counts.faults_injected);
    try std.testing.expectEqual(@as(usize, 4), read.counts.stepped_over);
    try std.testing.expectEqual(@as(usize, 1), read.counts.stalled);
}

test "a handover with no annotations reads back empty, with its counts" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const path = scratch ++ "/round-2/handover.txt";
    try handover.writeHandover(allocator, io, path, &.{}, &.{}, .{ .faults_injected = 7 });

    var read = try handover.readHandover(allocator, io, path);
    defer read.deinit();
    try std.testing.expectEqual(@as(usize, 0), read.annotations.len);
    try std.testing.expectEqual(@as(usize, 0), read.timings.len);
    try std.testing.expectEqual(@as(usize, 7), read.counts.faults_injected);
}

test "a line that does not parse is passed over rather than failing the read" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const path = scratch ++ "/broken/handover.txt";
    try std.Io.Dir.cwd().createDirPath(io, scratch ++ "/broken");
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = "A\tsrc/a.zig\ta:entered\t1\nT\tsrc/a.zig\tfirst\tnot-a-number\t3\nX\twhat\nC\t1\t2\t3\n",
    });

    var read = try handover.readHandover(allocator, io, path);
    defer read.deinit();
    try std.testing.expectEqual(@as(usize, 1), read.annotations.len);
    try std.testing.expectEqual(@as(usize, 0), read.timings.len);
    try std.testing.expectEqual(@as(usize, 2), read.counts.stepped_over);
}

test "the remaining list round-trips file, function and occurrence" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const functions = [_]handover.Function{
        .{ .file = "src/a.zig", .function = "first", .occurrence = 0 },
        .{ .file = "src/a.zig", .function = "first", .occurrence = 1 },
        .{ .file = "src/nested/b.zig", .function = "second", .occurrence = 0 },
    };
    const path = scratch ++ "/round-1/remaining.txt";
    try handover.writeRemaining(allocator, io, path, &functions);

    const read = try handover.readRemaining(allocator, io, path);
    defer handover.freeRemaining(allocator, read);

    try std.testing.expectEqual(@as(usize, 3), read.len);
    try std.testing.expectEqualStrings("src/a.zig", read[0].file);
    try std.testing.expectEqual(@as(usize, 1), read[1].occurrence);
    try std.testing.expectEqualStrings("second", read[2].function);
    try std.testing.expectEqualStrings("src/nested/b.zig", read[2].file);
}

test "an empty remaining list reads back as no functions" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const path = scratch ++ "/round-3/remaining.txt";
    try handover.writeRemaining(allocator, io, path, &.{});
    const read = try handover.readRemaining(allocator, io, path);
    defer handover.freeRemaining(allocator, read);
    try std.testing.expectEqual(@as(usize, 0), read.len);
}

test "reading a handover that is not there is an error, not an empty round" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    try std.testing.expectError(error.FileNotFound, handover.readHandover(allocator, threaded.io(), scratch ++ "/nowhere/handover.txt"));
}
