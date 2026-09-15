const std = @import("std");
const point_mod = @import("point.zig");
const Failure = point_mod.Failure;
const injector_mod = @import("injector.zig");
const Injector = injector_mod.Injector;
const plan_mod = @import("plan.zig");
const Plan = plan_mod.Plan;
const Injection = plan_mod.Injection;
const Invariant = @import("invariant.zig").Invariant;
const report = @import("report.zig");

// What is exercised through exhaustive fault injection: one function pointer with a context beside
// it, the shape `std.mem.Allocator` and this repository's own `Log` already use, so a subject is
// passed by value the same way either of them is. `run` takes the injector this run was built
// with and exercises the code under test through it, and has to leave nothing behind between calls:
// `exploreAll` calls it once for the clean pass and once per point and failure kind found, always
// from the same starting state.
pub const Subject = struct {
    ctx: *anyopaque,
    run: *const fn (ctx: *anyopaque, injector: *Injector) anyerror!void,
};

// What `exploreAll` is given: the subject to exercise, and what "handled correctly" means for it
// beyond "did not crash". A subject with nothing to check passes an empty slice.
// How many runs this exploration injected a fault into, for a caller that wants to say so. The
// clean pass is not counted: it fails nothing. Owned by the caller and written as the search goes,
// so the number is there whether the exploration finished or stopped on a failure.
pub const Counts = struct {
    injected_runs: usize = 0,
};

pub const ExploreOptions = struct {
    subject: Subject,
    invariants: []const Invariant = &.{},

    // Where to write what this exploration did, when the caller wants to print it.
    counts: ?*Counts = null,
};

// How often a sampled, expensive invariant runs: one call in this many injected runs, so a
// consistency pass that costs more than the injection it is checking still finishes in the time an
// ordinary suite takes. Named rather than inlined so the ratio is visible without reading the loop.
const sample_every = 8;

fn runInvariants(invariants: []const Invariant, run_index: usize) !void {
    for (invariants) |item| {
        switch (item.cost) {
            .cheap => try item.check(item.ctx),
            .expensive => if (run_index % sample_every == 0) {
                try item.check(item.ctx);
            },
        }
    }
}

// Exercises `options.subject` through every failure kind at every point its own clean run declares,
// one point and one kind at a time, so the failure that comes back belongs to the point that was
// failed. The clean pass comes first, with a recording injector that never fails
// anything, so a crash there is the subject's own defect rather than anything this loop injected.
// Everything the clean pass records becomes one injected run per failure kind it declared, in the
// order recorded, so exploring the same subject twice produces the same sequence of runs. A
// subject that returns an error, or an invariant that does not hold, both end the search
// immediately with the reproducing plan printed, because a seed alone does not say which point was
// failed.
pub fn exploreAll(allocator: std.mem.Allocator, options: ExploreOptions) !void {
    var recorder = Injector.initRecording(allocator);
    defer recorder.deinit();
    try options.subject.run(options.subject.ctx, &recorder);
    try runInvariants(options.invariants, 0);

    var run_index: usize = 1;
    for (recorder.recorded.items) |recorded| {
        for (recorded.failures) |failure| {
            const injections = [_]Injection{.{ .point = recorded.point, .failure = failure.name }};
            const plan: Plan = .{ .injections = &injections };
            var injecting = Injector.initReplaying(allocator, plan);
            defer injecting.deinit();

            if (options.counts) |counts| {
                counts.injected_runs += 1;
            }
            options.subject.run(options.subject.ctx, &injecting) catch |err| {
                report.printFailure(recorded.point, failure.name, err);
                return err;
            };
            runInvariants(options.invariants, run_index) catch |err| {
                report.printFailure(recorded.point, failure.name, err);
                return err;
            };
            run_index += 1;
        }
    }
}

// Runs `options.subject` once against exactly the plan given, for `--replay`: no recording, no
// sweep, straight to the one run a failure report named.
pub fn replay(allocator: std.mem.Allocator, options: ExploreOptions, plan: Plan) !void {
    var injecting = Injector.initReplaying(allocator, plan);
    defer injecting.deinit();
    try options.subject.run(options.subject.ctx, &injecting);
    try runInvariants(options.invariants, 0);
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("search.test.zig");
}
