// What a run prints when it is not finished: one line per thing somebody has to do, and one number
// saying how much of the code every path of has been run.
//
// The rest of the report says what happened. This says what to do about it, which is what somebody
// reading a red run actually needs: a file, a line, and the one action that ticks it.

const std = @import("std");
const Style = @import("style.zig").Style;
const output_mod = @import("output.zig");

// What kind of work one checklist line is asking for. Grouped by kind when printed, so the list is
// worked from the top rather than jumped about in.
pub const Kind = enum {
    // A branch carrying no annotation of its own, so nothing can say whether it ran.
    annotation,

    // A branch that is annotated but that nothing the run made up reached.
    scenario,

    // A parameter whose type the run cannot build, so the function is never called at all.
    value_factory,

    // A function with no `Log` parameter, so it has nowhere to send its annotations.
    log_parameter,

    // A module that would not compile because an import was not supplied.
    module,
};

// One thing to do. Every field that is not filled for a kind is left empty, and the printer reads
// only the ones that kind uses.
pub const Item = struct {
    kind: Kind,

    // Where the work is. A module item names the file that would not compile and has no line.
    file: []const u8 = "",
    line: u32 = 0,

    // The function the work is in, where there is one.
    function: []const u8 = "",

    // The annotation's own name, for a branch that is annotated but unreached.
    name: []const u8 = "",

    // Where the annotation goes, in words, for a branch that carries none.
    where: []const u8 = "",

    // The type a factory has to return, and where that type is declared.
    type_name: []const u8 = "",
    declared_at: []const u8 = "",

    // How many of a function's paths cannot be ticked because it has no `Log`.
    paths: usize = 0,

    // What the compiler said about a module that would not compile, and the name to supply.
    module_name: []const u8 = "",
    compiler_error: []const u8 = "",
};

// The order kinds are printed in: what stops a function being called at all comes first, because
// nothing below it can be worked until it is done, and the branches come last.
const kind_order = [_]Kind{ .module, .value_factory, .log_parameter, .annotation, .scenario };

// How a count reads at the head of the list. Written out up to twelve because "Three things to do"
// reads as a sentence and "3 things to do" reads as a log line; past that the digits are easier to
// take in than the word.
pub fn countWord(count: usize) []const u8 {
    return switch (count) {
        1 => "One",
        2 => "Two",
        3 => "Three",
        4 => "Four",
        5 => "Five",
        6 => "Six",
        7 => "Seven",
        8 => "Eight",
        9 => "Nine",
        10 => "Ten",
        11 => "Eleven",
        12 => "Twelve",
        else => "",
    };
}

// What a synthesized branch name says about where the annotation goes, in the words somebody would
// use for it. A synthesized name is `<kind>:<line>:<side>`, built by the coverage walker for a
// branch that carried no annotation of its own, so this reads that back.
//
// Returns null for a name that is not one of those, which is every annotation written by hand.
pub fn whereItGoes(allocator: std.mem.Allocator, name: []const u8) !?[]const u8 {
    const first = std.mem.indexOfScalar(u8, name, ':') orelse return null;
    const kind = name[0..first];
    const rest = name[first + 1 ..];
    const second = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    for (rest[0..second]) |character| {
        if (!std.ascii.isDigit(character)) {
            return null;
        }
    }
    const side = rest[second + 1 ..];

    if (std.mem.eql(u8, kind, "if")) {
        return try std.fmt.allocPrint(allocator, "on the {s} side of the if", .{side});
    }
    if (std.mem.eql(u8, kind, "switch")) {
        return try std.fmt.allocPrint(allocator, "on the {s} arm of the switch", .{side});
    }
    if (std.mem.eql(u8, kind, "loop")) {
        return try allocator.dupe(u8, "as the first statement of the loop body");
    }
    if (std.mem.eql(u8, kind, "catch")) {
        return try allocator.dupe(u8, "on the fallback side of the catch");
    }
    if (std.mem.eql(u8, kind, "orelse")) {
        return try allocator.dupe(u8, "on the fallback side of the orelse");
    }
    // `and`, `or` and `try` have nowhere to put an annotation at all, so they are never on this
    // list. Reaching here means the walker grew a kind this has not been told about, and saying so
    // is better than printing a line nobody can act on.
    return null;
}

// How many of these a terminal gets. The rest are in the report file, which holds every one of
// them with nothing left out.
//
// Ten because the list is already in the order the work is worth doing in, and a first run against
// a repository that has never been annotated produces thousands of these: printing them all buries
// the coverage number and the file that holds the rest under a wall nobody reads to the end of. Ten
// is enough to start on and short enough to read.
pub const terminal_limit = 10;

// How many of a list of `total` go to the terminal and how many are left for the report file. Its
// own function so the rule can be tested without reading what was printed.
pub fn terminalSplit(total: usize) struct { shown: usize, held_back: usize } {
    const shown = @min(total, terminal_limit);
    return .{ .shown = shown, .held_back = total - shown };
}

// Prints the list, grouped by kind, under a heading saying how many items there are.
//
// `report_path` is named on the line that says how many were not printed, so a reader who wants the
// rest never has to be told separately where they are.
pub fn print(items: []const Item, style: Style, report_path: []const u8) void {
    if (items.len == 0) {
        return;
    }

    const word = countWord(items.len);
    if (word.len != 0) {
        output_mod.print("\n  {s}{s} thing{s} to do:{s}\n", .{
            style.bold(),
            word,
            if (items.len == 1) "" else "s",
            style.reset(),
        });
    } else {
        output_mod.print("\n  {s}{d} things to do:{s}\n", .{ style.bold(), items.len, style.reset() });
    }

    var printed: usize = 0;
    for (kind_order) |kind| {
        for (items) |item| {
            if (item.kind != kind) {
                continue;
            }
            if (printed == terminal_limit) {
                continue;
            }
            printOne(item, style);
            printed += 1;
        }
    }

    if (items.len > printed) {
        output_mod.print("    {s}and {d} more, all of them in {s}.{s}\n", .{
            style.dim(),
            items.len - printed,
            report_path,
            style.reset(),
        });
    }
}

// One line of the list. Every one of them is a sentence: it says what to do, where, and why that is
// what is wanted, so it can be acted on without the rest of the report being read.
fn printOne(item: Item, style: Style) void {
    switch (item.kind) {
        .annotation => output_mod.print(
            "    {s}Add an annotation to {s}:{d}, {s} in {s}.{s}\n",
            .{ style.dim(), item.file, item.line, item.where, item.function, style.reset() },
        ),
        .scenario => output_mod.print(
            "    {s}Write a scenario reaching \"{s}\" at {s}:{d} in {s}. Nothing the run made up got there.{s}\n",
            .{ style.dim(), item.name, item.file, item.line, item.function, style.reset() },
        ),
        .value_factory => output_mod.print(
            "    {s}Write a test input factory returning {s}, which {s} takes. Without one, {s} at {s}:{d} cannot be called at all.{s}\n",
            .{ style.dim(), item.type_name, item.function, item.function, item.file, item.line, style.reset() },
        ),
        .log_parameter => output_mod.print(
            "    {s}Give {s} at {s}:{d} a Log parameter. It has nowhere to send its annotations, so none of its {d} paths can be ticked.{s}\n",
            .{ style.dim(), item.function, item.file, item.line, item.paths, style.reset() },
        ),
        .module => output_mod.print(
            "    {s}Supply the module {s}, which {s} imports and this run had no path for. Run again with --module {s}=<path>. The compiler said: {s}{s}\n",
            .{ style.dim(), item.module_name, item.file, item.module_name, item.compiler_error, style.reset() },
        ),
    }
}

// The one number a run ends on: how many of the paths it can observe were run. Unobservable
// branches are not in either count, so full coverage reads as 100% and is reachable.
pub fn printCoverage(ticked: usize, total: usize, style: Style) void {
    const percentage = percentageOf(ticked, total);
    const colour = if (percentage == 100) style.green() else style.red();
    output_mod.print(
        "\n  {s}{s}Coverage: {d} of {d} paths, {d}%.{s}\n\n",
        .{ colour, style.bold(), ticked, total, percentage, style.reset() },
    );
}

// What fraction of the paths ran, rounded down so a run one path short of everything never reads as
// 100%. A run with nothing to fault test is 100%: there is no path it failed to reach.
pub fn percentageOf(ticked: usize, total: usize) usize {
    if (total == 0) {
        return 100;
    }
    return ticked * 100 / total;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("checklist.test.zig");
}
