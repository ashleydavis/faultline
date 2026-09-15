// Where a run collects the annotations the code emitted, and the one way to point a `Log` at it.
//
// Kept out of `log.zig` so the log's own writing path stays traceable: a sink that lived
// beside the log would be a function the log annotates through, and annotating the sink would call
// the sink.

const std = @import("std");
const annotate_mod = @import("recording.zig");
const Log = annotate_mod.Log;
const Entry = annotate_mod.Entry;
const Detail = annotate_mod.Detail;

// Where a run collects the annotations the code emitted: a plain list, with no logging in it at
// all, which is what lets the log annotate its own writing path. Every entry is recorded at
// `.annotate`, so `trace.zig`'s helpers read this exactly as they read a `RecordingLog`'s entries.
pub const Annotations = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator) Annotations {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Annotations) void {
        for (self.entries.items) |recorded| {
            self.allocator.free(recorded.message);
            for (recorded.details) |detail| {
                self.allocator.free(detail.key);
                self.allocator.free(detail.value);
            }
            self.allocator.free(recorded.details);
        }
        self.entries.deinit(self.allocator);
    }

    // What a logger is constructed with, so its own writing path is traced too: those functions
    // annotate before they have a `Log` to hand.
    pub fn writer(self: *Annotations) annotate_mod.AnnotationWriter {
        return .{ .ctx = self, .record = append };
    }

    // Copies both strings, for the reason `RecordingLog` copies its own: most names and details are
    // formatted into a caller's stack buffer that is gone the moment it returns. An allocation
    // failure drops the annotation rather than failing the code being traced: this is an
    // instrument, and a dropped annotation shows up as an unticked path, loudly.
    fn append(ctx: *anyopaque, name: []const u8, detail: []const u8) void {
        const self: *Annotations = @ptrCast(@alignCast(ctx));
        const owned_name = self.allocator.dupe(u8, name) catch return;
        const details = self.allocator.alloc(Detail, 1) catch {
            self.allocator.free(owned_name);
            return;
        };
        const owned_key = self.allocator.dupe(u8, "detail") catch {
            self.allocator.free(details);
            self.allocator.free(owned_name);
            return;
        };
        const owned_detail = self.allocator.dupe(u8, detail) catch {
            self.allocator.free(owned_key);
            self.allocator.free(details);
            self.allocator.free(owned_name);
            return;
        };
        details[0] = .{ .key = owned_key, .value = owned_detail };
        self.entries.append(self.allocator, .{ .level = .annotate, .message = owned_name, .details = details }) catch {
            self.allocator.free(owned_detail);
            self.allocator.free(owned_key);
            self.allocator.free(details);
            self.allocator.free(owned_name);
        };
    }
};

// The same log, with its annotations going to `annotations` instead of nowhere.
pub fn tracingTo(log: Log, annotations: *Annotations) Log {
    var traced = log;
    traced.annotations = annotations.writer();
    return traced;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("annotations.test.zig");
}
