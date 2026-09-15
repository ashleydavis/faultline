// Tests for the annotation channel: what `annotate` records, where it sends it, and what a
// recording log keeps.

const std = @import("std");
const annotate_mod = @import("log.zig");
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

// A log that counts what reached its writing channel, so a test can show an annotation never went
// down it.
const CountingWrites = struct {
    count: usize = 0,

    fn log(self: *CountingWrites, sink: *Sink) Log {
        return .{ .ctx = self, .write = dispatch, .annotations = sink.writer() };
    }

    fn dispatch(ctx: *anyopaque, _: Level, _: []const u8, _: []const Detail) void {
        const self: *CountingWrites = @ptrCast(@alignCast(ctx));
        self.count += 1;
    }
};

test "annotate records the name it was given" {
    var sink = Sink{};
    const log = Log{ .annotations = sink.writer() };

    annotate_mod.annotate(log, "thing-entered", "", .{});

    try std.testing.expect(sink.sawName("thing-entered"));
    try std.testing.expectEqualStrings("", sink.detailFor("thing-entered").?);
}

test "annotate records a formatted detail beside the name" {
    var sink = Sink{};
    const log = Log{ .annotations = sink.writer() };

    annotate_mod.annotate(log, "counted", "{d} of {d}", .{ 3, 7 });

    try std.testing.expectEqualStrings("3 of 7", sink.detailFor("counted").?);
}

test "annotate records its own fallback when the detail will not fit" {
    var sink = Sink{};
    const log = Log{ .annotations = sink.writer() };

    annotate_mod.annotate(log, "over-long", "{s}", .{"n" ** 300});

    try std.testing.expect(sink.sawName("annotate-detail-too-long"));
    // The name stands in for the detail that would not fit, so the annotation is still recorded.
    try std.testing.expectEqualStrings("over-long", sink.detailFor("over-long").?);
}

test "annotate marks its own entry so the channel itself is traceable" {
    var sink = Sink{};
    const log = Log{ .annotations = sink.writer() };

    annotate_mod.annotate(log, "thing-entered", "", .{});

    try std.testing.expect(sink.sawName("annotate:entered"));
}

test "an annotation goes down the annotation channel and never down the writing one" {
    var sink = Sink{};
    var writes = CountingWrites{};
    const log = writes.log(&sink);

    annotate_mod.annotate(log, "thing-entered", "", .{});

    try std.testing.expect(sink.count != 0);
    try std.testing.expectEqual(@as(usize, 0), writes.count);
}

test "the default annotation writer drops an annotation nobody is recording" {
    const log = Log{};
    // Nothing records this, and nothing fails: a log with no sink is what a production build has.
    annotate_mod.annotate(log, "nowhere", "", .{});
}

test "the default write channel drops an entry nobody is keeping" {
    const log = Log{};
    log.write(log.ctx, .info, "nowhere", &.{});
}

test "an is on in a simulation build, which is what ticks a path" {
    try std.testing.expect(annotate_mod.an);
}
