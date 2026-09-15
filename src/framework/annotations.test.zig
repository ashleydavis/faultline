// Tests for the table a run collects its annotations into.

const std = @import("std");
const annotate_mod = @import("recording.zig");
const annotations_mod = @import("annotations.zig");

test "Annotations starts empty and releases what it kept" {
    var table = annotations_mod.Annotations.init(std.testing.allocator);
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 0), table.entries.items.len);
}

test "tracingTo points a log's annotations at the table and leaves the rest of it alone" {
    var table = annotations_mod.Annotations.init(std.testing.allocator);
    defer table.deinit();

    var recording = annotate_mod.RecordingLog{ .allocator = std.testing.allocator };
    defer recording.deinit();

    const traced = annotations_mod.tracingTo(recording.log(), &table);
    annotate_mod.annotate(traced, "reached", "", .{});

    try std.testing.expect(table.entries.items.len != 0);
    try std.testing.expectEqual(recording.log().write, traced.write);
}

test "an annotation is recorded at the annotate level, with its detail beside it" {
    var table = annotations_mod.Annotations.init(std.testing.allocator);
    defer table.deinit();

    const log = annotations_mod.tracingTo(.{}, &table);
    annotate_mod.annotate(log, "counted", "{d}", .{4});

    var found = false;
    for (table.entries.items) |entry| {
        if (!std.mem.eql(u8, entry.message, "counted")) {
            continue;
        }
        found = true;
        try std.testing.expectEqual(annotate_mod.Level.annotate, entry.level);
        try std.testing.expectEqualStrings("detail", entry.details[0].key);
        try std.testing.expectEqualStrings("4", entry.details[0].value);
    }
    try std.testing.expect(found);
}

test "the table copies the name it was handed" {
    var table = annotations_mod.Annotations.init(std.testing.allocator);
    defer table.deinit();

    const log = annotations_mod.tracingTo(.{}, &table);
    var name_buffer: [16]u8 = undefined;
    const name = try std.fmt.bufPrint(&name_buffer, "run-{d}", .{2});
    annotate_mod.annotate(log, name, "", .{});
    @memset(&name_buffer, 'x');

    var found = false;
    for (table.entries.items) |entry| {
        if (std.mem.eql(u8, entry.message, "run-2")) {
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "an annotation is dropped rather than failing the code when the allocator gives out" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var table = annotations_mod.Annotations.init(failing.allocator());
    defer table.deinit();

    const log = annotations_mod.tracingTo(.{}, &table);
    annotate_mod.annotate(log, "dropped", "", .{});

    try std.testing.expectEqual(@as(usize, 0), table.entries.items.len);
}

test "the table's writer is what a logger is constructed with" {
    var table = annotations_mod.Annotations.init(std.testing.allocator);
    defer table.deinit();

    var recording = annotate_mod.RecordingLog{ .allocator = std.testing.allocator, .annotations = table.writer() };
    defer recording.deinit();

    const log = recording.log();
    log.write(log.ctx, .info, "written", &.{});

    // The log's own writing path annotated through the table rather than through itself.
    try std.testing.expect(table.entries.items.len != 0);
}
