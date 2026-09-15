// Tests for the ready-made recorder a project that declares none of its own gets.

const std = @import("std");
const annotate_mod = @import("recording.zig");
const recorder_mod = @import("recorder.zig");

test "init builds the recorder in place, wired to the table beside it" {
    var recorder: recorder_mod.Recorder = undefined;
    recorder.init(std.testing.allocator);
    defer recorder.deinit();

    annotate_mod.annotate(recorder.log(), "reached", "", .{});

    try std.testing.expect(recorder.annotations.entries.items.len != 0);
}

test "log returns a log whose annotations reach this recorder" {
    var recorder: recorder_mod.Recorder = undefined;
    recorder.init(std.testing.allocator);
    defer recorder.deinit();

    const log = recorder.log();
    annotate_mod.annotate(log, "first", "", .{});
    annotate_mod.annotate(log, "second", "", .{});

    const names = try recorder.names(std.testing.allocator);
    defer {
        for (names) |name| std.testing.allocator.free(name);
        std.testing.allocator.free(names);
    }

    var saw_first = false;
    var saw_second = false;
    for (names) |name| {
        if (std.mem.eql(u8, name, "first")) saw_first = true;
        if (std.mem.eql(u8, name, "second")) saw_second = true;
    }
    try std.testing.expect(saw_first);
    try std.testing.expect(saw_second);
}

test "names copies what it hands back, so it outlives the recorder" {
    var recorder: recorder_mod.Recorder = undefined;
    recorder.init(std.testing.allocator);

    annotate_mod.annotate(recorder.log(), "kept", "", .{});
    const names = try recorder.names(std.testing.allocator);
    defer {
        for (names) |name| std.testing.allocator.free(name);
        std.testing.allocator.free(names);
    }

    recorder.deinit();

    var found = false;
    for (names) |name| {
        if (std.mem.eql(u8, name, "kept")) found = true;
    }
    try std.testing.expect(found);
}

test "names comes back empty from a recorder nothing annotated through" {
    var recorder: recorder_mod.Recorder = undefined;
    recorder.init(std.testing.allocator);
    defer recorder.deinit();

    const names = try recorder.names(std.testing.allocator);
    defer std.testing.allocator.free(names);
    try std.testing.expectEqual(@as(usize, 0), names.len);
}

test "names hands the allocation failure back rather than returning a short list" {
    var recorder: recorder_mod.Recorder = undefined;
    recorder.init(std.testing.allocator);
    defer recorder.deinit();

    annotate_mod.annotate(recorder.log(), "kept", "", .{});

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, recorder.names(failing.allocator()));
}

test "deinit releases the log and the table it held" {
    // The testing allocator fails the test if either is leaked, which is the whole assertion.
    var recorder: recorder_mod.Recorder = undefined;
    recorder.init(std.testing.allocator);
    const log = recorder.log();
    log.write(log.ctx, .info, "written", &.{});
    annotate_mod.annotate(log, "annotated", "", .{});
    recorder.deinit();
}
