// Recording what was annotated, which only the framework does.
//
// The channel itself is the `annotate` package, which the repository being fault tested depends on.
// This is the other end: what collects the names so a run can tick a checklist from them.

const std = @import("std");
const annotate_mod = @import("log");

pub const Level = annotate_mod.Level;
pub const Detail = annotate_mod.Detail;
pub const Log = annotate_mod.Log;
pub const AnnotationWriter = annotate_mod.AnnotationWriter;
pub const an = annotate_mod.an;
pub const annotate = annotate_mod.annotate;

// One recorded call to `write`: what `RecordingLog` stores, and what `trace.zig`'s helpers read.
pub const Entry = struct {
    // The level this was written at.
    level: Level,

    // The message, or an annotation's name.
    message: []const u8,

    // Structured detail carried alongside the message.
    details: []const Detail,
};

// A logger that keeps what it was given rather than writing it anywhere, so a test can read it
// back. Copies every string it is handed: a caller building a message with `std.fmt.bufPrint` into
// a stack buffer loses that buffer the moment it returns, so storing the slice directly would leave
// this holding a dangling pointer. Storing a copy is the only choice safe for both a
// stack-formatted message and a string literal, and it is what `deinit` frees.
pub const RecordingLog = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,

    // Where this logger's own trace points go, which is never itself.
    annotations: AnnotationWriter = .{},

    pub fn deinit(self: *RecordingLog) void {
        for (self.entries.items) |recorded| {
            if (an) annotate(self.log(), "deinit-entries-iteration", "", .{});
            self.allocator.free(recorded.message);
            for (recorded.details) |detail| {
                if (an) annotate(self.log(), "deinit-details-iteration", "", .{});
                self.allocator.free(detail.key);
                self.allocator.free(detail.value);
            }
            self.allocator.free(recorded.details);
        }
        self.entries.deinit(self.allocator);
    }

    fn dispatch(ctx: *anyopaque, level: Level, message: []const u8, details: []const Detail) void {
        const self: *RecordingLog = @ptrCast(@alignCast(ctx));
        // `Log.write` returns `void`, so there is nowhere to hand an allocation failure back to.
        // This is the one place here an error is swallowed rather than surfaced, and it is safe
        // only because this is a test double rather than the behaviour under test: a dropped
        // recording fails the assertion reading it, loudly, rather than silently passing.
        self.record(level, message, details) catch {
            if (an) annotate(self.log(), "dispatch-recording-dropped", "", .{});
            return;
        };
    }

    // The same work `dispatch` does through `Log.write`, but returning the allocation error rather
    // than swallowing it: `std.testing.checkAllAllocationFailures` needs a real error to propagate,
    // which a `void`-returning entry point cannot give it.
    pub fn record(self: *RecordingLog, level: Level, message: []const u8, details: []const Detail) !void {
        const owned_message = try self.allocator.dupe(u8, message);
        errdefer self.allocator.free(owned_message);

        const owned_details = try self.allocator.alloc(Detail, details.len);
        errdefer self.allocator.free(owned_details);
        var copied: usize = 0;
        errdefer {
            for (owned_details[0..copied]) |detail| {
                if (an) annotate(self.log(), "record-cleanup-iteration", "", .{});
                self.allocator.free(detail.key);
                self.allocator.free(detail.value);
            }
        }
        for (details, 0..) |detail, index| {
            if (an) annotate(self.log(), "record-details-iteration", "", .{});
            // `key` and `value` are duped one at a time, each with its own `errdefer`, rather than
            // both inside one struct literal: with both `try`s in the literal, a failing second
            // dupe would leak the first, since the literal as a whole never gets assigned to
            // `owned_details[index]` for `copied` to know about it.
            const owned_key = try self.allocator.dupe(u8, detail.key);
            errdefer self.allocator.free(owned_key);
            const owned_value = try self.allocator.dupe(u8, detail.value);
            owned_details[index] = .{ .key = owned_key, .value = owned_value };
            copied += 1;
        }
        try self.entries.append(self.allocator, .{ .level = level, .message = owned_message, .details = owned_details });
    }

    // Produces the `Log` value wired to this instance. Annotations are not recorded here: they go
    // to whatever `tracingTo` points this log at, which is a plain list with no logging in it.
    pub fn log(self: *RecordingLog) Log {
        const built: Log = .{ .ctx = self, .write = dispatch, .annotations = self.annotations };
        return built;
    }
};

// The rest of the recording side, re-exported here so the framework reaches all of it from one
// place.
pub const Annotations = @import("annotations.zig").Annotations;
pub const tracingTo = @import("annotations.zig").tracingTo;
pub const Recorder = @import("recorder.zig").Recorder;
pub const trace = @import("trace.zig");

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("recording.test.zig");
}
