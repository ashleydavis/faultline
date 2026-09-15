const std = @import("std");
const isolate = @import("isolate.zig");

// What a child says, and what the parent keeps, without any of the calls a real run makes. These
// tests are about the restart itself: what survives a child that dies, and what is stepped over.

fn sayThreeThings(plan: isolate.Plan, out: isolate.Emitter) void {
    var index: usize = 1;
    while (index <= 3) : (index += 1) {
        if (index < plan.start or plan.isSkipped(index)) {
            continue;
        }
        out.at(index);
        out.name(0, "reached");
    }
    out.done();
}

fn dieOnTheSecond(plan: isolate.Plan, out: isolate.Emitter) void {
    var index: usize = 1;
    while (index <= 3) : (index += 1) {
        if (index < plan.start or plan.isSkipped(index)) {
            continue;
        }
        out.at(index);
        if (index == 2) {
            // A child that dies is the ordinary case, so this stands in for a call whose arguments
            // were outside what the code accepts.
            std.process.abort();
        }
        out.name(0, "reached");
    }
    out.done();
}

test "a child that finishes hands back everything it said" {
    var collected: std.ArrayList([]const u8) = .empty;
    defer {
        for (collected.items) |line| std.testing.allocator.free(line);
        collected.deinit(std.testing.allocator);
    }

    const found = try isolate.attempt(.{}, sayThreeThings, &collected, std.testing.allocator);

    try std.testing.expect(found.finished);
    try std.testing.expect(!found.killed);
    try std.testing.expectEqual(@as(usize, 3), found.last_index);
    try std.testing.expectEqual(@as(usize, 3), collected.items.len);
}

test "a child that dies keeps what it said first and reports where it stopped" {
    var collected: std.ArrayList([]const u8) = .empty;
    defer {
        for (collected.items) |line| std.testing.allocator.free(line);
        collected.deinit(std.testing.allocator);
    }

    const found = try isolate.attempt(.{}, dieOnTheSecond, &collected, std.testing.allocator);

    try std.testing.expect(!found.finished);
    try std.testing.expect(found.killed);
    try std.testing.expect(!found.stalled);
    try std.testing.expectEqual(@as(usize, 2), found.last_index);
    try std.testing.expectEqual(@as(usize, 1), collected.items.len);
}

test "restarting steps over what killed the child and keeps the rest" {
    var collected: std.ArrayList([]const u8) = .empty;
    defer {
        for (collected.items) |line| std.testing.allocator.free(line);
        collected.deinit(std.testing.allocator);
    }

    const skipped = try isolate.exerciseUntilDone(dieOnTheSecond, &collected, std.testing.allocator);
    defer std.testing.allocator.free(skipped);

    // The one that died is stepped over, and the two either side of it are kept.
    try std.testing.expectEqual(@as(usize, 1), skipped.len);
    try std.testing.expectEqual(@as(usize, 2), skipped[0]);
    try std.testing.expectEqual(@as(usize, 2), collected.items.len);
}

test "a plan says what was stepped over and what lies in a range" {
    const plan: isolate.Plan = .{ .start = 4, .skipped = &.{ 2, 7 }, .stalled = &.{7} };

    try std.testing.expect(plan.isSkipped(2));
    try std.testing.expect(!plan.isSkipped(3));
    try std.testing.expect(plan.stalledWithin(5, 9));
    try std.testing.expect(!plan.stalledWithin(1, 5));
    try std.testing.expectEqual(@as(usize, 1), plan.skippedCountWithin(1, 5));
    try std.testing.expectEqual(@as(usize, 2), plan.skippedCountWithin(1, 9));
}

test "elapsed reads as seconds under a minute and as minutes and seconds above one" {
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("0s", isolate.elapsedText(&buffer, 0));
    try std.testing.expectEqualStrings("9s", isolate.elapsedText(&buffer, 9 * std.time.ns_per_s));
    try std.testing.expectEqualStrings("59s", isolate.elapsedText(&buffer, 59 * std.time.ns_per_s));
    try std.testing.expectEqualStrings("1m 0s", isolate.elapsedText(&buffer, 60 * std.time.ns_per_s));
    try std.testing.expectEqualStrings("2m 14s", isolate.elapsedText(&buffer, 134 * std.time.ns_per_s));
}
