// Tests for what a run prints when it is not finished.

const std = @import("std");
const checklist = @import("checklist.zig");
const output_mod = @import("output.zig");

// Reads back what a call printed, so a test can assert on the text rather than on the call not
// crashing. A run's report goes nowhere in a test build, so without this there is nothing to read.
//
// The caller owns what comes back.
fn printed(allocator: std.mem.Allocator, items: []const checklist.Item, report_path: []const u8) ![]u8 {
    var captured: std.Io.Writer.Allocating = .init(allocator);
    defer captured.deinit();

    output_mod.writer = &captured.writer;
    defer output_mod.writer = null;

    checklist.print(items, .init(false), report_path);
    return allocator.dupe(u8, captured.written());
}

test "countWord writes the count out up to twelve and stops there" {
    try std.testing.expectEqualStrings("One", checklist.countWord(1));
    try std.testing.expectEqualStrings("Three", checklist.countWord(3));
    try std.testing.expectEqualStrings("Twelve", checklist.countWord(12));
    try std.testing.expectEqualStrings("", checklist.countWord(13));
    try std.testing.expectEqualStrings("", checklist.countWord(0));
}

test "whereItGoes reads back each side of an if" {
    const allocator = std.testing.allocator;

    const true_side = (try checklist.whereItGoes(allocator, "if:34:true")).?;
    defer allocator.free(true_side);
    try std.testing.expectEqualStrings("on the true side of the if", true_side);

    const false_side = (try checklist.whereItGoes(allocator, "if:34:false")).?;
    defer allocator.free(false_side);
    try std.testing.expectEqualStrings("on the false side of the if", false_side);
}

test "whereItGoes names the switch arm the annotation belongs on" {
    const allocator = std.testing.allocator;
    const arm = (try checklist.whereItGoes(allocator, "switch:41:.gigabytes")).?;
    defer allocator.free(arm);
    try std.testing.expectEqualStrings("on the .gigabytes arm of the switch", arm);
}

test "whereItGoes says a loop wants both of its annotations" {
    const allocator = std.testing.allocator;
    const loop = (try checklist.whereItGoes(allocator, "loop:52:zero")).?;
    defer allocator.free(loop);
    try std.testing.expectEqualStrings("as the first statement of the loop body", loop);
}

test "whereItGoes reads a catch and an orelse" {
    const allocator = std.testing.allocator;

    const caught = (try checklist.whereItGoes(allocator, "catch:7:taken")).?;
    defer allocator.free(caught);
    try std.testing.expectEqualStrings("on the fallback side of the catch", caught);

    const fallen_back = (try checklist.whereItGoes(allocator, "orelse:9:taken")).?;
    defer allocator.free(fallen_back);
    try std.testing.expectEqualStrings("on the fallback side of the orelse", fallen_back);
}

test "whereItGoes says nothing about a name somebody wrote" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(@as(?[]const u8, null), try checklist.whereItGoes(allocator, "format-file-size-entered"));
    try std.testing.expectEqual(@as(?[]const u8, null), try checklist.whereItGoes(allocator, "if:notaline:true"));
    try std.testing.expectEqual(@as(?[]const u8, null), try checklist.whereItGoes(allocator, "plain"));
}

test "whereItGoes says nothing about a branch that can hold no annotation" {
    const allocator = std.testing.allocator;
    // `and`, `or` and `try` have nowhere to put one, so they are never on the list.
    try std.testing.expectEqual(@as(?[]const u8, null), try checklist.whereItGoes(allocator, "and:12:evaluated"));
    try std.testing.expectEqual(@as(?[]const u8, null), try checklist.whereItGoes(allocator, "or:12:short-circuit"));
    try std.testing.expectEqual(@as(?[]const u8, null), try checklist.whereItGoes(allocator, "try:12:failed"));
}

test "percentageOf rounds down, so one path short is never a hundred" {
    try std.testing.expectEqual(@as(usize, 100), checklist.percentageOf(10, 10));
    try std.testing.expectEqual(@as(usize, 99), checklist.percentageOf(999, 1000));
    try std.testing.expectEqual(@as(usize, 0), checklist.percentageOf(0, 10));
    try std.testing.expectEqual(@as(usize, 76), checklist.percentageOf(10, 13));
}

test "percentageOf is a hundred when there was nothing to fault test" {
    try std.testing.expectEqual(@as(usize, 100), checklist.percentageOf(0, 0));
}

test "print says nothing when there is nothing to do" {
    // An empty heading under a run that finished would read as work outstanding, so nothing at all
    // is the right output.
    const text = try printed(std.testing.allocator, &.{}, "report.txt");
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("", text);
}

test "print takes one item of every kind" {
    const items = [_]checklist.Item{
        .{ .kind = .annotation, .file = "src/format.zig", .line = 34, .function = "formatFileSize", .where = "on the false side of the if" },
        .{ .kind = .scenario, .file = "src/format.zig", .line = 59, .function = "formatFileSize", .name = "one-decimal" },
        .{ .kind = .value_factory, .file = "src/store.zig", .line = 21, .function = "openStore", .type_name = "Database" },
        .{ .kind = .log_parameter, .file = "src/hash.zig", .line = 12, .function = "hashBytes", .paths = 6 },
        .{ .kind = .module, .file = "src/uuid.zig", .module_name = "shortid", .compiler_error = "no module named 'shortid' available" },
    };
    const text = try printed(std.testing.allocator, &items, "report.txt");
    defer std.testing.allocator.free(text);

    // One line per item, under a heading that counts them, and every line carries the file it is
    // about so it can be acted on without the rest of the report being read.
    try std.testing.expect(std.mem.indexOf(u8, text, "Five things to do:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Add an annotation to src/format.zig:34") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Write a scenario reaching \"one-decimal\" at src/format.zig:59") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Write a test input factory returning Database") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Give hashBytes at src/hash.zig:12 a Log parameter") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Supply the module shortid") != null);

    // Everything fitted, so nothing is held back and the report file is not named.
    try std.testing.expect(std.mem.indexOf(u8, text, "more, all of them in") == null);
}

test "past the limit the rest are counted and the report file is named" {
    var many: [checklist.terminal_limit + 3]checklist.Item = undefined;
    for (&many) |*item| {
        item.* = .{ .kind = .annotation, .file = "src/wide.zig", .line = 1, .function = "wide", .where = "on the false side of the if" };
    }

    const text = try printed(std.testing.allocator, &many, "report.txt");
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "and 3 more, all of them in report.txt.") != null);

    // The limit is what was printed, not the whole list: one line per item plus the heading and the
    // line that counts the rest.
    var lines: usize = 0;
    var walk = std.mem.splitScalar(u8, text, '\n');
    while (walk.next()) |line| {
        if (std.mem.startsWith(u8, line, "    Add an annotation")) lines += 1;
    }
    try std.testing.expectEqual(checklist.terminal_limit, lines);
}

test "a short list goes to the terminal whole" {
    const split = checklist.terminalSplit(3);

    try std.testing.expectEqual(@as(usize, 3), split.shown);
    try std.testing.expectEqual(@as(usize, 0), split.held_back);
}

test "a list exactly at the limit is still printed whole" {
    const split = checklist.terminalSplit(checklist.terminal_limit);

    try std.testing.expectEqual(checklist.terminal_limit, split.shown);
    try std.testing.expectEqual(@as(usize, 0), split.held_back);
}

test "a first run against an unannotated repository holds thousands back for the report" {
    // The contract says the terminal gets a short report and the full list goes to a file. A run
    // against a repository that has never been annotated produces this many, and every one of them
    // on a terminal is the wall of text the promise exists to stop.
    const split = checklist.terminalSplit(2433);

    try std.testing.expectEqual(checklist.terminal_limit, split.shown);
    try std.testing.expectEqual(@as(usize, 2433 - checklist.terminal_limit), split.held_back);
}

test "nothing to do shows nothing and holds nothing back" {
    const split = checklist.terminalSplit(0);

    try std.testing.expectEqual(@as(usize, 0), split.shown);
    try std.testing.expectEqual(@as(usize, 0), split.held_back);
}
