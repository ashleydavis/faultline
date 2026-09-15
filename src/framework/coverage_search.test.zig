const std = @import("std");
const sim = @import("sim.zig");
const coverage = @import("coverage.zig");

// Two independent points; a branch only reached when both fail in the same run, which level 1
// (one fault per run) can never produce. Proves item 3: deepening while paths remain unticked, and
// stopping the instant they all are.
const two_point_source =
    \\fn twoPointScenario(first: bool, second: bool) void {
    \\    const combined: u8 = (@as(u8, @intFromBool(first)) << 1) | @intFromBool(second);
    \\    switch (combined) {
    \\        0b11 => {
    \\            if (an) annotate(log, "both-failed", "", .{});
    \\        },
    \\        0b10 => {
    \\            if (an) annotate(log, "first-failed", "", .{});
    \\        },
    \\        0b01 => {
    \\            if (an) annotate(log, "second-failed", "", .{});
    \\        },
    \\        else => {
    \\            if (an) annotate(log, "clean", "", .{});
    \\        },
    \\    }
    \\}
;

const one_failure = [_]sim.Failure{.{ .name = "fail", .err = error.Injected }};

// Exercises `twoPointScenario`'s own logic (not the parsed text above, which exists only to be read
// by `coverage.build`): two independent points, and the checklist ticked to match whichever of the
// four combinations this run's injector answers.
const TwoPointSubject = struct {
    calls: usize = 0,

    fn run(ctx: *anyopaque, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
        checklist.tickEntered();
        const self: *TwoPointSubject = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        const first = injector.check(@src(), 0, &one_failure) != null;
        const second = injector.check(@src(), 0, &one_failure) != null;
        if (first and second) {
            checklist.tick("both-failed");
        } else if (first) {
            checklist.tick("first-failed");
        } else if (second) {
            checklist.tick("second-failed");
        } else {
            checklist.tick("clean");
        }
    }
};

test "level 2 ticks a path that needs two simultaneous faults, and the search stops once everything is ticked" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", two_point_source, "twoPointScenario");
    defer checklist.deinit();

    var state = TwoPointSubject{};
    const subject: sim.CoverageSubject = .{ .ctx = &state, .run = TwoPointSubject.run };

    try sim.exploreCoverage(allocator, .{
        .subject = subject,
        .checklist = &checklist,
        .max_injected_runs = 100,
    });

    try std.testing.expect(checklist.allTicked());
    // The clean pass (1) plus level 1's two single-fault runs (2) plus level 2's one
    // both-simultaneously run (2 points choose 2 is exactly one combination, one failure each):
    // four calls total, none wasted once every path was ticked.
    try std.testing.expectEqual(@as(usize, 4), state.calls);
}

// A branch this runner never reaches, whatever is injected: proves item 4 (an unticked path is
// reported by function and line) and item 8 (a level ticking nothing new ends the bounded search)
// together, since both are the same run here.
const unreachable_source =
    \\fn unreachableScenario(flag: bool) void {
    \\    if (flag) {
    \\        if (an) annotate(log, "reachable", "", .{});
    \\    } else {
    \\        if (an) annotate(log, "never-reached", "", .{});
    \\    }
    \\}
;

const UnreachableSubject = struct {
    calls: usize = 0,

    fn run(ctx: *anyopaque, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
        checklist.tickEntered();
        const self: *UnreachableSubject = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        // Asks the injector so a point exists to explore, then ignores the answer entirely: this
        // runner always takes the "reachable" side, so "never-reached" can never tick no matter
        // how many levels the search tries.
        _ = injector.check(@src(), 0, &one_failure);
        checklist.tick("reachable");
    }
};

test "an unreachable branch ends the bounded search after one tickless level and is reported by function and line" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", unreachable_source, "unreachableScenario");
    defer checklist.deinit();

    var state = UnreachableSubject{};
    const subject: sim.CoverageSubject = .{ .ctx = &state, .run = UnreachableSubject.run };

    const result = sim.exploreCoverage(allocator, .{
        .subject = subject,
        .checklist = &checklist,
        .max_injected_runs = 1000,
    });
    try std.testing.expectError(error.CoverageLevelTicklessLimitReached, result);

    // The clean pass (1) plus level 1's one run (the single declared failure at the one point):
    // two calls, then the search stops rather than trying a level with no points left to combine.
    try std.testing.expectEqual(@as(usize, 2), state.calls);

    try std.testing.expect(!checklist.allTicked());
    try std.testing.expectEqual(@as(usize, 1), checklist.untickedCount());

    var written: std.Io.Writer.Allocating = .init(allocator);
    defer written.deinit();
    try checklist.report(&written.writer);
    try std.testing.expect(std.mem.indexOf(u8, written.written(), "unreachableScenario") != null);
    try std.testing.expect(std.mem.indexOf(u8, written.written(), "fixture.zig:2") != null);
    try std.testing.expect(std.mem.indexOf(u8, written.written(), "never-reached") != null);
}

// One point, five ways to fail, each ticking a distinct path so nothing here would ever look
// "tickless": proves item 9, that a ceiling on total injected runs ends the search regardless of
// whether ticking is still happening.
const many_failures_source =
    \\fn manyFailuresScenario(kind: u8) void {
    \\    switch (kind) {
    \\        1 => {
    \\            if (an) annotate(log, "kind-one", "", .{});
    \\        },
    \\        2 => {
    \\            if (an) annotate(log, "kind-two", "", .{});
    \\        },
    \\        3 => {
    \\            if (an) annotate(log, "kind-three", "", .{});
    \\        },
    \\        4 => {
    \\            if (an) annotate(log, "kind-other", "", .{});
    \\        },
    \\        else => {
    \\            if (an) annotate(log, "clean-kind", "", .{});
    \\        },
    \\    }
    \\}
;

const many_failures = [_]sim.Failure{
    .{ .name = "one", .err = error.Injected },
    .{ .name = "two", .err = error.Injected },
    .{ .name = "three", .err = error.Injected },
    .{ .name = "other", .err = error.Injected },
};

const ManyFailuresSubject = struct {
    fn run(ctx: *anyopaque, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
        checklist.tickEntered();
        _ = ctx;
        const chosen = injector.check(@src(), 0, &many_failures);
        const name = if (chosen) |failure| failure.name else "clean";
        if (std.mem.eql(u8, name, "one")) {
            checklist.tick("kind-one");
        } else if (std.mem.eql(u8, name, "two")) {
            checklist.tick("kind-two");
        } else if (std.mem.eql(u8, name, "three")) {
            checklist.tick("kind-three");
        } else if (std.mem.eql(u8, name, "other")) {
            checklist.tick("kind-other");
        } else {
            checklist.tick("clean-kind");
        }
    }
};

test "a ceiling on total injected runs ends the search even while every run is still ticking something new" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", many_failures_source, "manyFailuresScenario");
    defer checklist.deinit();

    var placeholder: u8 = 0;
    const subject: sim.CoverageSubject = .{ .ctx = &placeholder, .run = ManyFailuresSubject.run };

    const result = sim.exploreCoverage(allocator, .{
        .subject = subject,
        .checklist = &checklist,
        .max_injected_runs = 2,
    });
    try std.testing.expectError(error.CoverageRunCeilingReached, result);

    // The clean pass ticks "clean-kind"; the ceiling of 2 injected runs stops it after "one" and
    // "two" (the declared failure list's own order), leaving "three" and "other" unticked even
    // though nothing about this subject would ever have failed to tick them given more runs.
    try std.testing.expectEqual(@as(usize, 2), checklist.untickedCount());
}

// The same "never varies" runner as the unreachable-branch test above, but with three independent
// points to explore rather than one, so levels 1 through 3 each have a real combination to try
// without running out of points to combine. Proves item 10: `max_tickless_levels` widens how many
// consecutive unproductive levels the search tolerates before giving up, above the default of one.
const three_point_source =
    \\fn threePointScenario(flag: bool) void {
    \\    if (flag) {
    \\        if (an) annotate(log, "reachable", "", .{});
    \\    } else {
    \\        if (an) annotate(log, "never-reached", "", .{});
    \\    }
    \\}
;

const ThreePointSubject = struct {
    calls: usize = 0,

    fn run(ctx: *anyopaque, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
        checklist.tickEntered();
        const self: *ThreePointSubject = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        _ = injector.check(@src(), 0, &one_failure);
        _ = injector.check(@src(), 0, &one_failure);
        _ = injector.check(@src(), 0, &one_failure);
        checklist.tick("reachable");
    }
};

test "max_tickless_levels lets the search run through more unproductive levels before giving up" {
    const allocator = std.testing.allocator;

    var narrow_checklist = try coverage.build(allocator, "fixture.zig", three_point_source, "threePointScenario");
    defer narrow_checklist.deinit();
    var narrow_state = ThreePointSubject{};
    const narrow_subject: sim.CoverageSubject = .{ .ctx = &narrow_state, .run = ThreePointSubject.run };
    const narrow_result = sim.exploreCoverage(allocator, .{
        .subject = narrow_subject,
        .checklist = &narrow_checklist,
        .max_injected_runs = 1000,
    });
    try std.testing.expectError(error.CoverageLevelTicklessLimitReached, narrow_result);
    // Bounded tolerance of one: the clean pass (1) plus level 1's three single-point runs (3),
    // then it gives up rather than trying level 2 at all.
    try std.testing.expectEqual(@as(usize, 4), narrow_state.calls);

    var wide_checklist = try coverage.build(allocator, "fixture.zig", three_point_source, "threePointScenario");
    defer wide_checklist.deinit();
    var wide_state = ThreePointSubject{};
    const wide_subject: sim.CoverageSubject = .{ .ctx = &wide_state, .run = ThreePointSubject.run };
    const wide_result = sim.exploreCoverage(allocator, .{
        .subject = wide_subject,
        .checklist = &wide_checklist,
        .max_injected_runs = 1000,
        .max_tickless_levels = 3,
    });
    try std.testing.expectError(error.CoverageLevelTicklessLimitReached, wide_result);
    // A tolerance of three carries it through level 1 (3 runs), level 2 (3 points choose 2 is
    // three combinations, one run each) and level 3 (3 points choose 3 is one combination) before
    // giving up: 1 (clean) + 3 + 3 + 1 = 8 calls, double the narrow run above for the same subject.
    try std.testing.expectEqual(@as(usize, 8), wide_state.calls);
}

// A loop with the two plain annotations a loop carries, one immediately before it and one at the
// top of its body: item 6's own fixture, exercised at all three counts by varying the input rather
// than by injecting a fault, the "vary inputs and mocks" half of what a run ticks off. The code
// says only where the loop is and where an iteration begins; how many times it went round is the
// run's to count.
const loop_source =
    \\fn iterateItems(count: usize) void {
    \\    var index: usize = 0;
    \\    if (an) annotate(log, "iterate-loop", "", .{});
    \\    while (index < count) : (index += 1) {
    \\        if (an) annotate(log, "iterate-loop-iteration", "", .{});
    \\        doWork();
    \\    }
    \\}
;

// Runs the same loop `loop_source` describes, for real, at 0, 1 and 5 iterations in turn, handing
// the checklist what each run annotated in the order it annotated it: the loop's own name once,
// then the body's name once per iteration. Nothing here says which path that was, which is the
// point: the classification is the run's, from the count it read. The clean pass alone reaches
// every path, so `exploreCoverage` never needs to inject anything for this fixture.
const LoopSubject = struct {
    fn run(ctx: *anyopaque, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
        checklist.tickEntered();
        _ = ctx;
        _ = injector;
        for ([_]usize{ 0, 1, 5 }) |count| {
            // One for the loop itself and one per iteration, at the largest count exercised below.
            var names: [6][]const u8 = undefined;
            names[0] = "iterate-loop";
            var index: usize = 0;
            while (index < count) : (index += 1) {
                names[index + 1] = "iterate-loop-iteration";
            }
            checklist.tickFromTrace(names[0 .. count + 1]);
        }
    }
};

test "a loop is exercised at zero, one and many iterations, each ticking its own entry" {
    const allocator = std.testing.allocator;
    var checklist = try coverage.build(allocator, "fixture.zig", loop_source, "iterateItems");
    defer checklist.deinit();

    try std.testing.expectEqual(@as(usize, 4), checklist.paths.len);

    var placeholder: u8 = 0;
    const subject: sim.CoverageSubject = .{ .ctx = &placeholder, .run = LoopSubject.run };
    try sim.exploreCoverage(allocator, .{
        .subject = subject,
        .checklist = &checklist,
        .max_injected_runs = 100,
    });

    try std.testing.expect(checklist.allTicked());
}
