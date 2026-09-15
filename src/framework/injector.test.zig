// Tests for the thing a simulated effect asks whether it should fail right now.

const std = @import("std");
const injector_mod = @import("injector.zig");
const Injector = injector_mod.Injector;
const Plan = @import("plan.zig").Plan;
const Injection = @import("plan.zig").Injection;
const Failure = @import("point.zig").Failure;
const Point = @import("point.zig").Point;

const refused: Failure = .{ .name = "refused", .err = error.Refused };
const timed_out: Failure = .{ .name = "timed_out", .err = error.Timeout };
const kinds = [_]Failure{ refused, timed_out };

test "a recording injector fails nothing and keeps every point it was asked about" {
    var injector = Injector.initRecording(std.testing.allocator);
    defer injector.deinit();

    try std.testing.expectEqual(@as(?Failure, null), injector.check(@src(), 0, &kinds));
    try std.testing.expectEqual(@as(?Failure, null), injector.check(@src(), 0, &kinds));

    try std.testing.expectEqual(@as(usize, 2), injector.recorded.items.len);
    // The kinds are carried through as the effect declared them, so the search knows every way
    // each point can go wrong without asking again.
    try std.testing.expectEqual(@as(usize, 2), injector.recorded.items[0].failures.len);
    try std.testing.expectEqualStrings("refused", injector.recorded.items[0].failures[0].name);
    try std.testing.expectEqual(injector_mod.Mode.record, injector.mode);
}

test "a recording injector keeps two points on one line apart by their occurrence" {
    var injector = Injector.initRecording(std.testing.allocator);
    defer injector.deinit();

    _ = injector.check(@src(), 0, &kinds);
    _ = injector.check(@src(), 1, &kinds);

    try std.testing.expectEqual(@as(u16, 0), injector.recorded.items[0].point.occurrence);
    try std.testing.expectEqual(@as(u16, 1), injector.recorded.items[1].point.occurrence);
}

test "a replaying injector fails exactly the point its plan names, and nothing else" {
    const here = @src();
    const injections = [_]Injection{
        .{ .point = .{ .file = here.file, .line = here.line, .occurrence = 0 }, .failure = "timed_out" },
    };
    var injector = Injector.initReplaying(std.testing.allocator, .{ .injections = &injections });
    defer injector.deinit();

    const at_the_named_point = injector.check(here, 0, &kinds);
    try std.testing.expectEqualStrings("timed_out", at_the_named_point.?.name);
    try std.testing.expectEqual(@as(anyerror, error.Timeout), at_the_named_point.?.err);

    // A different occurrence on the same line is a different point.
    try std.testing.expectEqual(@as(?Failure, null), injector.check(here, 1, &kinds));
    try std.testing.expectEqual(injector_mod.Mode.replay, injector.mode);
}

test "a replaying injector answers nothing where the plan names a failure the effect cannot have" {
    const here = @src();
    const injections = [_]Injection{
        .{ .point = .{ .file = here.file, .line = here.line, .occurrence = 0 }, .failure = "something_else" },
    };
    var injector = Injector.initReplaying(std.testing.allocator, .{ .injections = &injections });
    defer injector.deinit();

    try std.testing.expectEqual(@as(?Failure, null), injector.check(here, 0, &kinds));
}

test "a replaying injector with an empty plan fails nothing" {
    var injector = Injector.initReplaying(std.testing.allocator, .{ .injections = &.{} });
    defer injector.deinit();

    try std.testing.expectEqual(@as(?Failure, null), injector.check(@src(), 0, &kinds));
}

test "a recorded point carries where it was and what it declared" {
    const recorded: injector_mod.Recorded = .{
        .point = .{ .file = "a.sim.zig", .line = 1, .occurrence = 0 },
        .failures = &kinds,
    };
    try std.testing.expect(recorded.point.eql(.{ .file = "a.sim.zig", .line = 1, .occurrence = 0 }));
    try std.testing.expectEqual(@as(usize, 2), recorded.failures.len);
}
