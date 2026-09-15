// Whether a function's calls are still reaching anything they had not reached before.
//
// How many times a function is called is decided from its parameter types, which says how rare a
// particular combination of arguments is and nothing at all about how many code paths the function
// has. A function whose arguments are a union of structs of slices is therefore called thousands of
// times whether it has three paths or thirty, and once the last of them has been reached every
// remaining call re-runs paths already covered. That was most of what `zig build sim` spent its
// time on: the run is meant to reach every code path, not every combination of inputs.
//
// So each call reports what it annotated, and a function's calls stop once enough of them in a row
// have annotated nothing new. What counts as new is deliberately wider than a checklist path: a
// name never seen before, and also a name seen before but this time not at all, once, or more than
// once, since that is what decides a loop's zero, one and many paths. Being wider means this keeps
// going in cases where the checklist would already be full, which costs calls, while the other way
// round would cost coverage.

const std = @import("std");

// How many buckets a count falls into, and which. A loop path turns on whether a traversal went
// round no times, once, or more, so those are the three worth telling apart; anything above two
// tells a caller nothing a two did not.
const bucket_zero: u8 = 1;
const bucket_one: u8 = 2;
const bucket_many: u8 = 4;

fn bucketOf(count: usize) u8 {
    if (count == 0) {
        return bucket_zero;
    }
    if (count == 1) {
        return bucket_one;
    }
    return bucket_many;
}

pub const Progress = struct {
    allocator: std.mem.Allocator,

    // Every name this function's calls have annotated, against the buckets it has been seen in.
    // The names are copies: what a call reports lives in that call's arena and is gone by the next.
    seen: std.StringHashMapUnmanaged(u8) = .empty,

    // How many times each name was annotated by the call being looked at. Kept between calls so it
    // is cleared and refilled rather than rebuilt, since this runs once per call for the whole run.
    counts: std.StringHashMapUnmanaged(usize) = .empty,

    pub fn init(allocator: std.mem.Allocator) Progress {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Progress) void {
        var names = self.seen.keyIterator();
        while (names.next()) |name| {
            self.allocator.free(name.*);
        }
        self.seen.deinit(self.allocator);
        self.counts.deinit(self.allocator);
    }

    // Takes in what one call annotated, in the order it annotated it, and says whether any of it
    // had not been seen from this function before.
    //
    // Out of memory here is reported as new, which is the safe answer: it keeps the function's
    // calls going rather than ending them on the strength of a record that failed to be kept.
    pub fn observe(self: *Progress, names: []const []const u8) bool {
        self.countThisCall(names) catch return true;

        var fresh = false;

        // The buckets first, over the names already known, because this call's count for a name it
        // does not carry is zero and a zero is as much a path as a one is.
        var known = self.seen.iterator();
        while (known.next()) |entry| {
            const count = self.counts.get(entry.key_ptr.*) orelse 0;
            const bucket = bucketOf(count);
            if (entry.value_ptr.* & bucket == 0) {
                entry.value_ptr.* |= bucket;
                fresh = true;
            }
        }

        // Then the names this call brought that nothing had annotated before. Added after the walk
        // above rather than during it, because inserting into a map being iterated is undefined.
        var reported = self.counts.iterator();
        while (reported.next()) |entry| {
            if (self.seen.contains(entry.key_ptr.*)) {
                continue;
            }
            const kept = self.allocator.dupe(u8, entry.key_ptr.*) catch return true;
            self.seen.put(self.allocator, kept, bucketOf(entry.value_ptr.*)) catch {
                self.allocator.free(kept);
                return true;
            };
            fresh = true;
        }

        return fresh;
    }

    fn countThisCall(self: *Progress, names: []const []const u8) !void {
        self.counts.clearRetainingCapacity();
        for (names) |name| {
            const found = try self.counts.getOrPut(self.allocator, name);
            if (found.found_existing) {
                found.value_ptr.* += 1;
            } else {
                found.value_ptr.* = 1;
            }
        }
    }
};

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("progress.test.zig");
}
