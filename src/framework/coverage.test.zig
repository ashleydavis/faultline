const std = @import("std");
const coverage = @import("coverage.zig");

// A small, self-contained function to read: an `if` with one side annotated and one side not, a
// three-way `switch` with one case annotated, a `while` loop with the one annotation a loop carries
// at the top of its body, and, deliberately, one `if (an) annotate(...)` guard of its own to prove
// it is never counted as a path. None of `an`, `annotate`, `log` or the called functions need to exist: `std.zig.Ast` only
// parses this, it never resolves an identifier or runs anything.
const fixture_source =
    \\fn sample(flag: bool, count: usize, choice: u8) void {
    \\    if (flag) {
    \\        doSomething();
    \\    } else {
    \\        if (an) annotate(log, "flag-was-false", "", .{});
    \\    }
    \\
    \\    switch (choice) {
    \\        1 => {
    \\            caseOne();
    \\        },
    \\        2 => {
    \\            if (an) annotate(log, "case-two", "", .{});
    \\        },
    \\        else => {
    \\            caseElse();
    \\        },
    \\    }
    \\
    \\    var index: usize = 0;
    \\    while (index < count) : (index += 1) {
    \\        if (an) annotate(log, "sample-loop-iteration", "", .{});
    \\        doWork();
    \\    }
    \\}
;

// Item 1: `std.zig.Ast` reads a function's own source and the produced list matches the branches
// actually in it, checked as an exact set of (line, name) pairs rather than a count, so a branch
// landing at the wrong line would fail this as surely as a missing one.
test "build reads a function's branches from its own source" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", fixture_source, "sample");
    defer checklist.deinit();

    try std.testing.expectEqualStrings("sample", checklist.function);
    // Six branch sides, plus the function's own entry path.
    try std.testing.expectEqual(@as(usize, 7), checklist.paths.len);

    const Expected = struct { line: u32, name: []const u8 };
    const expected = [_]Expected{
        .{ .line = 2, .name = "if:2:true" },
        .{ .line = 4, .name = "flag-was-false" },
        .{ .line = 9, .name = "switch:9:1" },
        .{ .line = 12, .name = "case-two" },
        .{ .line = 15, .name = "switch:15:else" },
        .{ .line = 21, .name = "sample-loop-iteration" },
    };
    for (expected) |want| {
        var found = false;
        for (checklist.paths) |got| {
            if (got.line == want.line and std.mem.eql(u8, got.name, want.name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("missing expected path: {d} \"{s}\"\n", .{ want.line, want.name });
        }
        try std.testing.expect(found);
    }
}

// Item 5: the comptime-known guard itself never appears in the list. A walker that did not
// exclude it would find each `if (an) annotate(...)` line as an if-statement of its own and produce
// two paths for every annotation in the fixture.
test "if (an) annotate(...) is never a path" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", fixture_source, "sample");
    defer checklist.deinit();

    for (checklist.paths) |path| {
        try std.testing.expect(!std.mem.eql(u8, path.name, "an"));
        for ([_]u32{ 5, 13, 22 }) |guard_line| {
            try std.testing.expect(path.line != guard_line);
        }
    }
}

// Item 6: a loop is one entry, its body, named by the one annotation written inside it.
test "a loop produces one entry, named by the annotation in its body" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", fixture_source, "sample");
    defer checklist.deinit();

    try std.testing.expect(hasPath(checklist, "sample-loop-iteration"));
    try std.testing.expect(!hasPath(checklist, "sample-loop:zero"));
    try std.testing.expect(!hasPath(checklist, "sample-loop:one"));
    try std.testing.expect(!hasPath(checklist, "sample-loop:many"));
}

fn hasPath(checklist: coverage.Checklist, name: []const u8) bool {
    for (checklist.paths) |path| {
        if (std.mem.eql(u8, path.name, name)) {
            return true;
        }
    }
    return false;
}

// A run ticks entries off the list, and `report` says which ran and which did not: item 2's
// "something a reader can open".
test "tick marks a path reached, and report says so" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", fixture_source, "sample");
    defer checklist.deinit();

    checklist.tick("flag-was-false");

    var written: std.Io.Writer.Allocating = .init(allocator);
    defer written.deinit();
    try checklist.report(&written.writer);

    try std.testing.expect(std.mem.indexOf(u8, written.written(), "ticked fixture.zig:4 \"flag-was-false\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, written.written(), "UNTICKED") != null);
    try std.testing.expect(!checklist.allTicked());
}

test "tick on a name build never produced panics rather than silently doing nothing" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", fixture_source, "sample");
    defer checklist.deinit();

    // `std.testing.expectEqual` cannot assert a panic; this proves the path list is exactly what
    // the earlier test names instead, which is what makes an unrecognised name in `tick` always a
    // caller defect.
    try std.testing.expect(!hasPath(checklist, "does-not-exist"));
}

// A function with no branches at all still builds, with an empty checklist rather than an error:
// this is what lets `build` be called uniformly before anything is known about the function.
test "a function with no branches has one path, its own entry" {
    const allocator = std.testing.allocator;
    const source =
        \\fn plain(value: i64) i64 {
        \\    return value + 1;
        \\}
    ;
    var checklist = try coverage.build(allocator, "fixture.zig", source, "plain");
    defer checklist.deinit();

    try std.testing.expectEqual(@as(usize, 1), checklist.paths.len);
    try std.testing.expectEqualStrings("plain:entered", checklist.paths[0].name);
    try std.testing.expect(!checklist.allTicked());

    checklist.tickEntered();
    try std.testing.expect(checklist.allTicked());
}

test "build reports an error for a function name not in the source" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        error.FunctionNotFound,
        coverage.build(allocator, "fixture.zig", fixture_source, "doesNotExist"),
    );
}

// Two functions sharing a name because each sits in a different container, the way `log.zig`'s
// `WriterLog.dispatch`/`RecordingLog.dispatch` and `random_generator.zig`'s bare `random`/
// `ScriptedRandom.random` each do. `build`'s plain name search can only ever find the first;
// `buildOccurrence` is what tells the second one apart.
const duplicate_name_source =
    \\const First = struct {
    \\    fn shared(value: i64) i64 {
    \\        return value;
    \\    }
    \\};
    \\const Second = struct {
    \\    fn shared(value: i64) i64 {
    \\        if (value > 0) {
    \\            return value;
    \\        }
    \\        return 0;
    \\    }
    \\};
;

test "build always finds the first declaration sharing a name" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", duplicate_name_source, "shared");
    defer checklist.deinit();

    // `First.shared` has no branch of its own, so its checklist is its entry path alone;
    // `Second.shared` has one `if`. Finding the first proves `build` did not read the second.
    try std.testing.expectEqual(@as(usize, 1), checklist.paths.len);
    try std.testing.expectEqualStrings("shared:entered", checklist.paths[0].name);
}

test "buildOccurrence reads the second declaration sharing a name" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.buildOccurrence(allocator, "fixture.zig", duplicate_name_source, "shared", 1);
    defer checklist.deinit();

    // Its own entry path, plus both sides of its one `if`.
    try std.testing.expectEqual(@as(usize, 3), checklist.paths.len);
}

test "buildOccurrence(0) is the same declaration build finds" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.buildOccurrence(allocator, "fixture.zig", duplicate_name_source, "shared", 0);
    defer checklist.deinit();

    try std.testing.expectEqual(@as(usize, 1), checklist.paths.len);
    try std.testing.expectEqualStrings("shared:entered", checklist.paths[0].name);
}

test "buildOccurrence reports an error past the last declaration sharing a name" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        error.FunctionNotFound,
        coverage.buildOccurrence(allocator, "fixture.zig", duplicate_name_source, "shared", 2),
    );
}

// Item 1's other half: an enumeration over a whole file, rather than one named function, is what
// lets a build ask "does every function this file declares have a checklist" without a person
// reading the file to check. Every function in `duplicate_name_source` above, plus the shared name
// twice, so this also proves `listDeclarations` numbers duplicates the same way `buildOccurrence`
// expects them named.
test "listDeclarations lists every function, numbering same-named ones by occurrence" {
    const allocator = std.testing.allocator;
    const declarations = try coverage.listDeclarations(allocator, duplicate_name_source);
    defer coverage.freeDeclarations(allocator, declarations);

    try std.testing.expectEqual(@as(usize, 2), declarations.len);
    try std.testing.expectEqualStrings("shared", declarations[0].name);
    try std.testing.expectEqual(@as(usize, 0), declarations[0].occurrence);
    try std.testing.expectEqualStrings("shared", declarations[1].name);
    try std.testing.expectEqual(@as(usize, 1), declarations[1].occurrence);
}

test "listDeclarations finds a function reading its own source, not by name" {
    const allocator = std.testing.allocator;
    const declarations = try coverage.listDeclarations(allocator, fixture_source);
    defer coverage.freeDeclarations(allocator, declarations);

    try std.testing.expectEqual(@as(usize, 1), declarations.len);
    try std.testing.expectEqualStrings("sample", declarations[0].name);
    try std.testing.expectEqual(@as(usize, 0), declarations[0].occurrence);
}

test "listDeclarations reports an error for text that does not parse as Zig" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        error.SourceDoesNotParse,
        coverage.listDeclarations(allocator, "fn broken( {"),
    );
}

// One Zig control-flow form per fixture, so the walker's coverage of the language itself is a
// thing a reader can check by reading this table rather than by trusting the walker. Each entry
// names the form, a function using it, and how many paths that function's branches must produce
// beyond the function's own entry path. A form the walker cannot see produces fewer paths than
// the count beside it and fails here, which is what makes a hole in the walker visible without
// anybody having to notice it in a real file.
const FormCase = struct {
    form: []const u8,
    source: [:0]const u8,
    branch_paths: usize,
};

const form_cases = [_]FormCase{
    .{
        .form = "if statement, both sides written",
        .branch_paths = 2,
        .source =
        \\fn sample(flag: bool) void {
        \\    if (flag) {
        \\        one();
        \\    } else {
        \\        two();
        \\    }
        \\}
        ,
    },
    .{
        .form = "if statement with no else",
        .branch_paths = 2,
        .source =
        \\fn sample(flag: bool) void {
        \\    if (flag) {
        \\        one();
        \\    }
        \\}
        ,
    },
    .{
        .form = "if with an optional capture",
        .branch_paths = 2,
        .source =
        \\fn sample(value: ?u8) void {
        \\    if (value) |inner| {
        \\        one(inner);
        \\    }
        \\}
        ,
    },
    .{
        .form = "if with an error union capture and an else capture",
        .branch_paths = 2,
        .source =
        \\fn sample() void {
        \\    if (call()) |value| {
        \\        one(value);
        \\    } else |err| {
        \\        two(err);
        \\    }
        \\}
        ,
    },
    .{
        .form = "if used as a value",
        .branch_paths = 2,
        .source =
        \\fn sample(flag: bool) u8 {
        \\    const chosen = if (flag) one() else two();
        \\    return chosen;
        \\}
        ,
    },
    .{
        .form = "switch statement with an else arm",
        .branch_paths = 3,
        .source =
        \\fn sample(choice: u8) void {
        \\    switch (choice) {
        \\        1 => one(),
        \\        2 => two(),
        \\        else => other(),
        \\    }
        \\}
        ,
    },
    .{
        .form = "switch used as a value",
        .branch_paths = 3,
        .source =
        \\fn sample(choice: u8) u8 {
        \\    return switch (choice) {
        \\        1 => one(),
        \\        2 => two(),
        \\        else => other(),
        \\    };
        \\}
        ,
    },
    .{
        .form = "switch with a range arm and a multi-value arm",
        .branch_paths = 3,
        .source =
        \\fn sample(choice: u8) u8 {
        \\    return switch (choice) {
        \\        0...9 => one(),
        \\        10, 11 => two(),
        \\        else => other(),
        \\    };
        \\}
        ,
    },
    .{
        .form = "while loop",
        .branch_paths = 1,
        .source =
        \\fn sample(count: usize) void {
        \\    var index: usize = 0;
        \\    while (index < count) : (index += 1) {
        \\        work();
        \\    }
        \\}
        ,
    },
    .{
        .form = "while loop with a capture",
        .branch_paths = 1,
        .source =
        \\fn sample(source: anytype) void {
        \\    while (source.next()) |item| {
        \\        work(item);
        \\    }
        \\}
        ,
    },
    .{
        .form = "for loop",
        .branch_paths = 1,
        .source =
        \\fn sample(items: []const u8) void {
        \\    for (items) |item| {
        \\        work(item);
        \\    }
        \\}
        ,
    },
    .{
        .form = "catch with a capture",
        .branch_paths = 1,
        .source =
        \\fn sample() void {
        \\    call() catch |err| {
        \\        handle(err);
        \\    };
        \\}
        ,
    },
    .{
        .form = "catch used as a value",
        .branch_paths = 1,
        .source =
        \\fn sample() u8 {
        \\    const value = call() catch 0;
        \\    return value;
        \\}
        ,
    },
    .{
        .form = "orelse",
        .branch_paths = 1,
        .source =
        \\fn sample(value: ?u8) u8 {
        \\    return value orelse 0;
        \\}
        ,
    },
    .{
        .form = "try",
        .branch_paths = 1,
        .source =
        \\fn sample() !u8 {
        \\    const value = try call();
        \\    return value;
        \\}
        ,
    },
    .{
        .form = "and short-circuit",
        .branch_paths = 2,
        .source =
        \\fn sample(first: bool, second: bool) bool {
        \\    return first and second;
        \\}
        ,
    },
    .{
        .form = "or short-circuit",
        .branch_paths = 2,
        .source =
        \\fn sample(first: bool, second: bool) bool {
        \\    return first or second;
        \\}
        ,
    },
    .{
        .form = "branch inside a catch body",
        .branch_paths = 3,
        .source =
        \\fn sample() u8 {
        \\    return call() catch |err| {
        \\        if (err == error.Missing) {
        \\            return 1;
        \\        }
        \\        return 2;
        \\    };
        \\}
        ,
    },
    .{
        .form = "branch inside a defer body",
        .branch_paths = 2,
        .source =
        \\fn sample(flag: bool) void {
        \\    defer {
        \\        if (flag) {
        \\            one();
        \\        }
        \\    }
        \\    work();
        \\}
        ,
    },
    .{
        .form = "branch inside an errdefer body",
        .branch_paths = 3,
        .source =
        \\fn sample(flag: bool) !void {
        \\    errdefer {
        \\        if (flag) {
        \\            one();
        \\        }
        \\    }
        \\    try work();
        \\}
        ,
    },
    .{
        .form = "loop with an else clause",
        .branch_paths = 4,
        .source =
        \\fn sample(items: []const u8) u8 {
        \\    for (items) |item| {
        \\        if (item == 1) break;
        \\    } else {
        \\        return 0;
        \\    }
        \\    return 1;
        \\}
        ,
    },
    .{
        .form = "labelled block broken out of with a value",
        .branch_paths = 2,
        .source =
        \\fn sample(flag: bool) u8 {
        \\    return blk: {
        \\        if (flag) break :blk 1;
        \\        break :blk 2;
        \\    };
        \\}
        ,
    },
    .{
        .form = "inline for",
        .branch_paths = 1,
        .source =
        \\fn sample(comptime items: []const u8) void {
        \\    inline for (items) |item| {
        \\        work(item);
        \\    }
        \\}
        ,
    },
    .{
        .form = "switch inside a catch capture",
        .branch_paths = 3,
        .source =
        \\fn sample() u8 {
        \\    return call() catch |err| switch (err) {
        \\        error.Missing => 1,
        \\        else => 2,
        \\    };
        \\}
        ,
    },
};

// Every form above, one test, so a failure names the form that is not being seen rather than a
// count that has drifted. `branch_paths` excludes the function's own entry path, which every
// checklist carries.
test "the walker sees every Zig control-flow form" {
    const allocator = std.testing.allocator;
    var missed: usize = 0;
    for (form_cases) |form_case| {
        var checklist = try coverage.build(allocator, "fixture.zig", form_case.source, "sample");
        defer checklist.deinit();

        const found = checklist.paths.len - 1;
        if (found != form_case.branch_paths) {
            missed += 1;
            std.debug.print(
                "form not fully seen: {s}: expected {d} branch path(s), found {d}\n",
                .{ form_case.form, form_case.branch_paths, found },
            );
            for (checklist.paths) |path| {
                std.debug.print("    line {d} \"{s}\"\n", .{ path.line, path.name });
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 0), missed);
}

// The three forms with nowhere to put a statement are marked as such, and everything else is not,
// so a run can tell a branch it failed to exercise apart from one it could never observe.
test "a short-circuit, a try, and the side of an `if` that carries on are what no annotation reaches" {
    const allocator = std.testing.allocator;
    const source =
        \\fn sample(first: bool, second: bool) !u8 {
        \\    if (first and second) {
        \\        one();
        \\    }
        \\    const value = try call();
        \\    return value;
        \\}
    ;
    var checklist = try coverage.build(allocator, "fixture.zig", source, "sample");
    defer checklist.deinit();

    var unobservable: usize = 0;
    for (checklist.paths) |path| {
        if (path.observable) continue;
        unobservable += 1;
        const is_short_circuit = std.mem.startsWith(u8, path.name, "and:") or std.mem.startsWith(u8, path.name, "or:");
        const is_try = std.mem.startsWith(u8, path.name, "try:");
        // The `if` here has no `else` and its taken side carries on, so both sides meet at the
        // statement after it and nothing there says which one happened.
        const is_the_side_that_carries_on = std.mem.eql(u8, path.name, "if:2:false");
        try std.testing.expect(is_short_circuit or is_try or is_the_side_that_carries_on);
    }
    // Both sides of the `and`, the one `try`, and the side of the `if` that carries on.
    try std.testing.expectEqual(@as(usize, 4), unobservable);

    for (checklist.paths) |path| {
        if (std.mem.eql(u8, path.name, "if:2:true") or std.mem.endsWith(u8, path.name, ":entered")) {
            try std.testing.expect(path.observable);
        }
    }
}

// A branch written inside a value, which is where the walker was blind: the `if` inside this
// `catch` body is a path exactly as it would be at the top of the function.
test "a branch inside a catch body is a path" {
    const allocator = std.testing.allocator;
    const source =
        \\fn sample() u8 {
        \\    return call() catch |err| {
        \\        if (err == error.Missing) {
        \\            return 1;
        \\        }
        \\        return 2;
        \\    };
        \\}
    ;
    var checklist = try coverage.build(allocator, "fixture.zig", source, "sample");
    defer checklist.deinit();

    var found_if = false;
    for (checklist.paths) |path| {
        if (std.mem.eql(u8, path.name, "if:3:true")) found_if = true;
    }
    try std.testing.expect(found_if);
}

