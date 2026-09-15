const std = @import("std");
const annotate = log_mod.annotate;
const an = log_mod.an;
const Log = log_mod.Log;
const log_mod = @import("recording.zig");
const Entry = log_mod.Entry;

// The trace vocabulary every package reaches for when asserting on a `RecordingLog`'s entries,
// written once here rather than reinvented per package. Each function reads a list of recorded
// entries (an event's or an annotation's `message` field is what it matches on: both carry a name
// there) and returns an error a test propagates with `try`, naming the specific way the trace
// failed to match what was expected.
pub const TraceError = error{
    // `expectSeen`: no entry's message matched.
    NotSeen,
    // `expectNever`: an entry's message matched, and none was wanted.
    UnexpectedlySeen,
    // `expectCount`: the number of matching entries was not the number expected.
    WrongCount,
    // `expectOrder`: the names did not appear as a subsequence in the given order.
    OutOfOrder,
    // `expectBalanced`: "begin-<name>" and "end-<name>" did not occur the same number of times.
    Unbalanced,
    // `expectBalanced`: `name` is too long for the fixed buffer used to build "begin-"/"end-".
    NameTooLong,
    // `expectNeverBetween`: the forbidden name appeared between the start and end names.
    ForbiddenBetween,
};

pub fn countMatching(entries: []const Entry, name: []const u8, log: Log) usize {

    var count: usize = 0;
    for (entries) |entry| {
        if (an) annotate(log, "countMatching-loop-1-iteration", "", .{});
        if (std.mem.eql(u8, entry.message, name)) {
            if (an) annotate(log, "countMatching-branch-1", "", .{});
            count += 1;
        } else {
            if (an) annotate(log, "countMatching-else-1", "", .{});
        }
    }
    return count;
}

// Asserts `name` was recorded at least once.
pub fn expectSeen(entries: []const Entry, name: []const u8, log: Log) TraceError!void {
    if (countMatching(entries, name, log) == 0) {
        if (an) annotate(log, "expectSeen-branch-1", "", .{});
        return TraceError.NotSeen;
    } else {
        if (an) annotate(log, "expectSeen-else-1", "", .{});
    }
}

// Asserts `name` was never recorded. This is the one a fault-injection run uses to prove recovery
// happened rather than the fault never having been injected: inject the fault, run the code, then
// assert the fallback name it would have hit was never seen.
pub fn expectNever(entries: []const Entry, name: []const u8, log: Log) TraceError!void {
    if (countMatching(entries, name, log) != 0) {
        if (an) annotate(log, "expectNever-branch-1", "", .{});
        return TraceError.UnexpectedlySeen;
    } else {
        if (an) annotate(log, "expectNever-else-1", "", .{});
    }
}

// Asserts `name` was recorded exactly `expected_count` times.
pub fn expectCount(entries: []const Entry, name: []const u8, expected_count: usize, log: Log) TraceError!void {
    if (countMatching(entries, name, log) != expected_count) {
        if (an) annotate(log, "expectCount-branch-1", "", .{});
        return TraceError.WrongCount;
    } else {
        if (an) annotate(log, "expectCount-else-1", "", .{});
    }
}

// Asserts `names` appear as a subsequence of the recorded messages, in the given order. Entries
// between two wanted names, and repeats of a name already matched, do not break the match: this is
// a subsequence check, not an adjacency check.
pub fn expectOrder(entries: []const Entry, names: []const []const u8, log: Log) TraceError!void {
    var next_index: usize = 0;
    for (entries) |entry| {
        if (an) annotate(log, "expectOrder-loop-1-iteration", "", .{});
        if (next_index >= names.len) {
            if (an) annotate(log, "expectOrder-branch-1", "", .{});
            break;
        } else {
            if (an) annotate(log, "expectOrder-else-1", "", .{});
        }
        if (std.mem.eql(u8, entry.message, names[next_index])) {
            if (an) annotate(log, "expectOrder-branch-2", "", .{});
            next_index += 1;
        } else {
            if (an) annotate(log, "expectOrder-else-2", "", .{});
        }
    }
    if (next_index != names.len) {
        if (an) annotate(log, "expectOrder-branch-3", "", .{});
        return TraceError.OutOfOrder;
    } else {
        if (an) annotate(log, "expectOrder-else-3", "", .{});
    }
}

// Asserts "begin-<name>" and "end-<name>" were recorded the same number of times, so a resource
// opened is always closed. An error path that records "begin-<name>" and returns before recording
// "end-<name>" fails this, which is the point: a test on that path uses `expectBalanced` to prove
// the code left something open, or a test on the happy path uses it to prove the code did not.
pub fn expectBalanced(entries: []const Entry, name: []const u8, log: Log) TraceError!void {
    var begin_buffer: [128]u8 = undefined;
    var end_buffer: [128]u8 = undefined;
    const begin_name = std.fmt.bufPrint(&begin_buffer, "begin-{s}", .{name}) catch {
        if (an) annotate(log, "expectBalanced-begin-name-too-long", "", .{});
        return TraceError.NameTooLong;
    };
    // Both buffers are the same size and the `begin-` prefix is the longer of the two, so a name
    // that would overflow this one has already returned at `begin_name` above.
    const end_name = std.fmt.bufPrint(&end_buffer, "end-{s}", .{name}) catch unreachable;

    if (countMatching(entries, begin_name, log) != countMatching(entries, end_name, log)) {

        if (an) annotate(log, "expectBalanced-branch-1", "", .{});
        return TraceError.Unbalanced;
    } else {

        if (an) annotate(log, "expectBalanced-else-1", "", .{});

    }
}

// Asserts `forbidden_name` never appears between the first `start_name` and the `end_name` that
// follows it. Entries before `start_name` or after `end_name`, and a `forbidden_name` that never
// appears at all, do not fail this.
pub fn expectNeverBetween(
    entries: []const Entry,
    start_name: []const u8,
    end_name: []const u8,
    forbidden_name: []const u8,
log: Log) TraceError!void {
    var inside = false;
    for (entries) |entry| {
        if (an) annotate(log, "expectNeverBetween-loop-1-iteration", "", .{});
        if (!inside and std.mem.eql(u8, entry.message, start_name)) {
            if (an) annotate(log, "expectNeverBetween-branch-1", "", .{});
            inside = true;
            continue;
        } else {
            if (an) annotate(log, "expectNeverBetween-else-1", "", .{});
        }
        if (inside and std.mem.eql(u8, entry.message, end_name)) {
            if (an) annotate(log, "expectNeverBetween-branch-2", "", .{});
            inside = false;
            continue;
        } else {
            if (an) annotate(log, "expectNeverBetween-else-2", "", .{});
        }
        if (inside and std.mem.eql(u8, entry.message, forbidden_name)) {
            if (an) annotate(log, "expectNeverBetween-branch-3", "", .{});
            return TraceError.ForbiddenBetween;
        } else {
            if (an) annotate(log, "expectNeverBetween-else-3", "", .{});
        }
    }
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what makes `zig build test` run it.
    //
    _ = @import("trace.test.zig");
}
