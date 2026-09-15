// The recorder a run reads its annotations back off, ready made.
//
// A project that declares no `Recorder` of its own gets this one. A project that already has a
// logger declares its own beside its log type, and a run finds that instead. Either way the
// framework only ever calls `init`, `log`, `names` and `deinit`.

const std = @import("std");
const annotate_mod = @import("recording.zig");
const annotations_mod = @import("annotations.zig");
const Log = annotate_mod.Log;

// This module's `RecordingLog` with the annotations table beside it, and the `Log` the code being
// fault tested annotates through, which is wired to both.
//
// It is built where it will live and `init` is called on it there, because `wired` points at
// `recording` and `annotations` beside it: a value that moved after being wired would leave that
// log pointing at the address it came from.
pub const Recorder = struct {
    recording: annotate_mod.RecordingLog = undefined,
    annotations: annotations_mod.Annotations = undefined,
    wired: Log = undefined,

    pub fn init(self: *Recorder, allocator: std.mem.Allocator) void {
        self.* = .{
            .recording = .{ .allocator = allocator },
            .annotations = annotations_mod.Annotations.init(allocator),
        };
        self.wired = annotations_mod.tracingTo(self.recording.log(), &self.annotations);
    }

    pub fn log(self: *Recorder) Log {
        return self.wired;
    }

    // The names every scenario emitted, owned by the caller: what they were read out of dies with
    // this recorder, so they are copied rather than borrowed.
    //
    // Written here rather than called out of the framework, which has the same function, so the
    // annotation channel does not import the framework: a project can annotate its code and assert
    // on what it annotated without the simulation framework being in the build at all.
    pub fn names(self: *Recorder, allocator: std.mem.Allocator) anyerror![]const []const u8 {
        const entries = self.annotations.entries.items;
        const collected = try allocator.alloc([]const u8, entries.len);
        var written: usize = 0;
        errdefer {
            for (collected[0..written]) |name| allocator.free(name);
            allocator.free(collected);
        }
        for (entries) |entry| {
            collected[written] = try allocator.dupe(u8, entry.message);
            written += 1;
        }
        return collected;
    }

    pub fn deinit(self: *Recorder) void {
        self.annotations.deinit();
        self.recording.deinit();
    }
};

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("recorder.test.zig");
}
