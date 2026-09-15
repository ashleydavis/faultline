// Tests for the search: the clean pass first, then one fault per run at every point it recorded.

const std = @import("std");
const search = @import("search.zig");
const Injector = @import("injector.zig").Injector;
const Invariant = @import("invariant.zig").Invariant;
const Failure = @import("point.zig").Failure;
const Plan = @import("plan.zig").Plan;
const Injection = @import("plan.zig").Injection;

const kinds = [_]Failure{
    .{ .name = "refused", .err = error.Refused },
    .{ .name = "timed_out", .err = error.Timeout },
};

// A subject with one point that can fail two ways, which counts its own runs.
const OnePoint = struct {
    runs: usize = 0,
    failures_taken: usize = 0,

    // Set to end the run with an error the moment the point fails, for the case about a subject
    // that does not survive what was injected.
    surrender: bool = false,

    fn run(ctx: *anyopaque, injector: *Injector) anyerror!void {
        const self: *OnePoint = @ptrCast(@alignCast(ctx));
        self.runs += 1;
        if (injector.check(@src(), 0, &kinds)) |failure| {
            self.failures_taken += 1;
            if (self.surrender) {
                return failure.err;
            }
        }
    }

    fn subject(self: *OnePoint) search.Subject {
        return .{ .ctx = self, .run = OnePoint.run };
    }
};

// A subject with two points, to show every point is explored rather than only the first.
const TwoPoints = struct {
    runs: usize = 0,

    fn run(ctx: *anyopaque, injector: *Injector) anyerror!void {
        const self: *TwoPoints = @ptrCast(@alignCast(ctx));
        self.runs += 1;
        _ = injector.check(@src(), 0, &kinds);
        _ = injector.check(@src(), 0, &kinds);
    }

    fn subject(self: *TwoPoints) search.Subject {
        return .{ .ctx = self, .run = TwoPoints.run };
    }
};

test "the clean pass runs first, then one run per failure kind at each point" {
    var subject = OnePoint{};
    var counts: search.Counts = .{};
    try search.exploreAll(std.testing.allocator, .{ .subject = subject.subject(), .counts = &counts });

    // One clean pass, then one run per kind the point declared.
    try std.testing.expectEqual(@as(usize, 1 + kinds.len), subject.runs);
    try std.testing.expectEqual(@as(usize, kinds.len), counts.injected_runs);
    try std.testing.expectEqual(@as(usize, kinds.len), subject.failures_taken);
}

test "every point is explored, not only the first" {
    var subject = TwoPoints{};
    var counts: search.Counts = .{};
    try search.exploreAll(std.testing.allocator, .{ .subject = subject.subject(), .counts = &counts });

    // Two points, two kinds each.
    try std.testing.expectEqual(@as(usize, 4), counts.injected_runs);
    try std.testing.expectEqual(@as(usize, 5), subject.runs);
}

test "a subject with nothing that can fail gets the clean pass and no more" {
    const Nothing = struct {
        runs: usize = 0,
        fn run(ctx: *anyopaque, _: *Injector) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.runs += 1;
        }
    };
    var subject = Nothing{};
    var counts: search.Counts = .{};
    try search.exploreAll(std.testing.allocator, .{
        .subject = .{ .ctx = &subject, .run = Nothing.run },
        .counts = &counts,
    });

    try std.testing.expectEqual(@as(usize, 1), subject.runs);
    try std.testing.expectEqual(@as(usize, 0), counts.injected_runs);
}

test "a subject that does not survive an injected fault ends the search with its own error" {
    var subject = OnePoint{ .surrender = true };
    try std.testing.expectError(
        error.Refused,
        search.exploreAll(std.testing.allocator, .{ .subject = subject.subject() }),
    );
    // The search stopped at the first failure rather than carrying on through the rest.
    try std.testing.expectEqual(@as(usize, 2), subject.runs);
}

// An invariant that counts how often it was checked, and can be made to refuse.
const Counted = struct {
    checks: usize = 0,
    holds: bool = true,

    fn check(ctx: *anyopaque) anyerror!void {
        const self: *Counted = @ptrCast(@alignCast(ctx));
        self.checks += 1;
        if (!self.holds) {
            return error.DidNotHold;
        }
    }
};

test "a cheap invariant is checked after the clean pass and after every injected run" {
    var subject = OnePoint{};
    var counted = Counted{};
    const invariants = [_]Invariant{
        .{ .name = "cheap", .cost = .cheap, .ctx = &counted, .check = Counted.check },
    };
    try search.exploreAll(std.testing.allocator, .{
        .subject = subject.subject(),
        .invariants = &invariants,
    });

    try std.testing.expectEqual(subject.runs, counted.checks);
}

test "an expensive invariant is sampled rather than checked every time" {
    var subject = OnePoint{};
    var counted = Counted{};
    const invariants = [_]Invariant{
        .{ .name = "expensive", .cost = .expensive, .ctx = &counted, .check = Counted.check },
    };
    try search.exploreAll(std.testing.allocator, .{
        .subject = subject.subject(),
        .invariants = &invariants,
    });

    // Fewer checks than runs is the whole point of sampling: a consistency pass that costs more
    // than the injection it is checking would otherwise decide how long the run takes.
    try std.testing.expect(counted.checks < subject.runs);
    try std.testing.expect(counted.checks != 0);
}

test "an invariant that does not hold ends the search with its own error" {
    var subject = OnePoint{};
    var counted = Counted{ .holds = false };
    const invariants = [_]Invariant{
        .{ .name = "cheap", .cost = .cheap, .ctx = &counted, .check = Counted.check },
    };
    try std.testing.expectError(error.DidNotHold, search.exploreAll(std.testing.allocator, .{
        .subject = subject.subject(),
        .invariants = &invariants,
    }));
}

test "a replay runs once against exactly the plan it was given" {
    var subject = OnePoint{};
    const here = @src();
    // The point the subject asks about is inside its own `run`, so the plan names that file and a
    // line the test does not know; replaying a plan that names nothing still runs it once.
    _ = here;
    const injections = [_]Injection{};
    try search.replay(std.testing.allocator, .{ .subject = subject.subject() }, .{ .injections = &injections });

    try std.testing.expectEqual(@as(usize, 1), subject.runs);
    try std.testing.expectEqual(@as(usize, 0), subject.failures_taken);
}

test "a replay checks the invariants too" {
    var subject = OnePoint{};
    var counted = Counted{};
    const invariants = [_]Invariant{
        .{ .name = "cheap", .cost = .cheap, .ctx = &counted, .check = Counted.check },
    };
    try search.replay(
        std.testing.allocator,
        .{ .subject = subject.subject(), .invariants = &invariants },
        .{ .injections = &.{} },
    );

    try std.testing.expectEqual(@as(usize, 1), counted.checks);
}

test "a replay hands back the error a failing subject returned" {
    const Refusing = struct {
        fn run(_: *anyopaque, _: *Injector) anyerror!void {
            return error.Refused;
        }
    };
    var nothing: usize = 0;
    try std.testing.expectError(error.Refused, search.replay(
        std.testing.allocator,
        .{ .subject = .{ .ctx = &nothing, .run = Refusing.run } },
        .{ .injections = &.{} },
    ));
}

test "counts start at nothing" {
    const counts: search.Counts = .{};
    try std.testing.expectEqual(@as(usize, 0), counts.injected_runs);
}
