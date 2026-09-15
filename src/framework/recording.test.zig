// Tests for the recording half of the annotation channel, which only the framework uses.

const std = @import("std");
const annotate_mod = @import("recording.zig");
const annotations_mod = @import("annotations.zig");
const Log = annotate_mod.Log;
const Level = annotate_mod.Level;
const Detail = annotate_mod.Detail;

// A sink that keeps the names and details it was handed, in storage of its own. It copies both,
// because `annotate` formats its detail into a stack buffer that is gone the moment it returns,
// which is the same reason every real sink copies. Nothing here allocates, so a test that only
// wants to know what was annotated has nothing to release.
const Sink = struct {
    // Room for more annotations than any test here emits, and for a name and a detail longer than
    // any of them writes. Anything past either is dropped rather than growing the fixture.
    const most_entries = 64;
    const longest_text = 512;

    names: [most_entries][longest_text]u8 = undefined,
    name_lengths: [most_entries]usize = undefined,
    details: [most_entries][longest_text]u8 = undefined,
    detail_lengths: [most_entries]usize = undefined,
    count: usize = 0,

    fn writer(self: *Sink) annotate_mod.AnnotationWriter {
        return .{ .ctx = self, .record = append };
    }

    fn append(ctx: *anyopaque, name: []const u8, detail: []const u8) void {
        const self: *Sink = @ptrCast(@alignCast(ctx));
        if (self.count == most_entries or name.len > longest_text or detail.len > longest_text) {
            return;
        }
        @memcpy(self.names[self.count][0..name.len], name);
        self.name_lengths[self.count] = name.len;
        @memcpy(self.details[self.count][0..detail.len], detail);
        self.detail_lengths[self.count] = detail.len;
        self.count += 1;
    }

    fn nameAt(self: *Sink, index: usize) []const u8 {
        return self.names[index][0..self.name_lengths[index]];
    }

    fn sawName(self: *Sink, wanted: []const u8) bool {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (std.mem.eql(u8, self.nameAt(index), wanted)) {
                return true;
            }
        }
        return false;
    }

    fn detailFor(self: *Sink, wanted: []const u8) ?[]const u8 {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            if (std.mem.eql(u8, self.nameAt(index), wanted)) {
                return self.details[index][0..self.detail_lengths[index]];
            }
        }
        return null;
    }
};

test "RecordingLog keeps an entry, with its message and details copied" {
    var recording = annotate_mod.RecordingLog{ .allocator = std.testing.allocator };
    defer recording.deinit();

    var message_buffer: [32]u8 = undefined;
    const message = try std.fmt.bufPrint(&message_buffer, "built at {d}", .{7});
    try recording.record(.info, message, &.{.{ .key = "where", .value = "here" }});
    // Overwriting the buffer the message was formatted into shows the entry kept a copy.
    @memset(&message_buffer, 'x');

    try std.testing.expectEqual(@as(usize, 1), recording.entries.items.len);
    try std.testing.expectEqualStrings("built at 7", recording.entries.items[0].message);
    try std.testing.expectEqualStrings("where", recording.entries.items[0].details[0].key);
    try std.testing.expectEqualStrings("here", recording.entries.items[0].details[0].value);
}

test "RecordingLog keeps entries in the order they were written" {
    var recording = annotate_mod.RecordingLog{ .allocator = std.testing.allocator };
    defer recording.deinit();

    try recording.record(.info, "first", &.{});
    try recording.record(.warn, "second", &.{});

    try std.testing.expectEqualStrings("first", recording.entries.items[0].message);
    try std.testing.expectEqualStrings("second", recording.entries.items[1].message);
    try std.testing.expectEqual(Level.warn, recording.entries.items[1].level);
}

test "RecordingLog drops an entry rather than failing the call when the allocator gives out" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var recording = annotate_mod.RecordingLog{ .allocator = failing.allocator() };
    defer recording.deinit();

    const log = recording.log();
    log.write(log.ctx, .info, "dropped", &.{});

    try std.testing.expectEqual(@as(usize, 0), recording.entries.items.len);
}

test "RecordingLog hands its allocation failure back through record" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var recording = annotate_mod.RecordingLog{ .allocator = failing.allocator() };
    defer recording.deinit();

    try std.testing.expectError(error.OutOfMemory, recording.record(.info, "dropped", &.{}));
}

test "RecordingLog's log is wired to it, and to whatever is recording its annotations" {
    var sink = Sink{};
    var recording = annotate_mod.RecordingLog{ .allocator = std.testing.allocator, .annotations = sink.writer() };
    defer recording.deinit();

    const log = recording.log();
    log.write(log.ctx, .info, "written", &.{});

    try std.testing.expectEqualStrings("written", recording.entries.items[0].message);
    try std.testing.expect(sink.sawName("dispatch:entered"));
}

test "the annotate module re-exports the rest of the channel" {
    // A project imports one module and has all of it, so these four have to be reachable from here.
    try std.testing.expect(@TypeOf(annotate_mod.Annotations) == type);
    try std.testing.expect(@TypeOf(annotate_mod.Recorder) == type);
    try std.testing.expect(@TypeOf(annotate_mod.tracingTo) == @TypeOf(annotations_mod.tracingTo));
    try std.testing.expect(@hasDecl(annotate_mod.trace, "expectSeen"));
}
