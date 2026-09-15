// Tests for the assertions over what a run annotated: a passing case and a failing case each.

const std = @import("std");
const annotate_mod = @import("recording.zig");
const trace = @import("trace.zig");
const Entry = annotate_mod.Entry;

// A trace built from names alone, which is all any of these assertions read.
fn entriesOf(comptime names: []const []const u8) [names.len]Entry {
    var built: [names.len]Entry = undefined;
    for (names, 0..) |name, index| {
        built[index] = .{ .level = .annotate, .message = name, .details = &.{} };
    }
    return built;
}

const quiet: annotate_mod.Log = .{};

test "countMatching counts every entry carrying the name" {
    var entries = entriesOf(&.{ "a", "b", "a", "c" });
    try std.testing.expectEqual(@as(usize, 2), trace.countMatching(&entries, "a", quiet));
    try std.testing.expectEqual(@as(usize, 0), trace.countMatching(&entries, "missing", quiet));
    var none = entriesOf(&.{});
    try std.testing.expectEqual(@as(usize, 0), trace.countMatching(&none, "a", quiet));
}

test "expectSeen passes when the name is there and fails when it is not" {
    var entries = entriesOf(&.{ "opened", "closed" });
    try trace.expectSeen(&entries, "opened", quiet);
    try std.testing.expectError(trace.TraceError.NotSeen, trace.expectSeen(&entries, "flushed", quiet));
}

test "expectNever passes when the name is absent and fails when it is there" {
    var entries = entriesOf(&.{ "opened", "closed" });
    try trace.expectNever(&entries, "flushed", quiet);
    try std.testing.expectError(trace.TraceError.UnexpectedlySeen, trace.expectNever(&entries, "opened", quiet));
}

test "expectCount passes on the exact number and fails on any other" {
    var entries = entriesOf(&.{ "tick", "tick", "tock" });
    try trace.expectCount(&entries, "tick", 2, quiet);
    try std.testing.expectError(trace.TraceError.WrongCount, trace.expectCount(&entries, "tick", 3, quiet));
}

test "expectOrder passes when the names are a subsequence and fails when they are not" {
    var entries = entriesOf(&.{ "first", "middle", "second", "last" });
    try trace.expectOrder(&entries, &.{ "first", "second" }, quiet);
    try std.testing.expectError(
        trace.TraceError.OutOfOrder,
        trace.expectOrder(&entries, &.{ "second", "first" }, quiet),
    );
}

test "expectOrder fails when one of the names is not there at all" {
    var entries = entriesOf(&.{ "first", "second" });
    try std.testing.expectError(
        trace.TraceError.OutOfOrder,
        trace.expectOrder(&entries, &.{ "first", "third" }, quiet),
    );
}

test "expectBalanced passes on matching begins and ends and fails when one is missing" {
    var balanced = entriesOf(&.{ "begin-work", "end-work", "begin-work", "end-work" });
    try trace.expectBalanced(&balanced, "work", quiet);

    var unbalanced = entriesOf(&.{ "begin-work", "end-work", "begin-work" });
    try std.testing.expectError(trace.TraceError.Unbalanced, trace.expectBalanced(&unbalanced, "work", quiet));
}

test "expectBalanced refuses a name too long for the buffer it builds" {
    var entries = entriesOf(&.{});
    const long_name = "n" ** 512;
    try std.testing.expectError(trace.TraceError.NameTooLong, trace.expectBalanced(&entries, long_name, quiet));
}

test "expectNeverBetween passes when the forbidden name is outside and fails when it is inside" {
    var outside = entriesOf(&.{ "locked", "opened", "closed", "unlocked" });
    try trace.expectNeverBetween(&outside, "opened", "closed", "locked", quiet);

    var inside = entriesOf(&.{ "opened", "locked", "closed" });
    try std.testing.expectError(
        trace.TraceError.ForbiddenBetween,
        trace.expectNeverBetween(&inside, "opened", "closed", "locked", quiet),
    );
}

test "expectNeverBetween passes when the span never opened" {
    var entries = entriesOf(&.{ "locked", "unlocked" });
    try trace.expectNeverBetween(&entries, "opened", "closed", "locked", quiet);
}
