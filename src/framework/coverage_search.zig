const std = @import("std");
const injector_mod = @import("injector.zig");
const Injector = injector_mod.Injector;
const Recorded = injector_mod.Recorded;
const plan_mod = @import("plan.zig");
const Plan = plan_mod.Plan;
const Injection = plan_mod.Injection;
const coverage_mod = @import("coverage.zig");
const Checklist = coverage_mod.Checklist;

// Drives a `CoverageSubject` through its own checklist (`coverage.zig`), deepening how many faults
// land at once while any path stays unticked. The checklist comes from the parser, for the
// function under test only. Bounded three ways, so a run that could not cover everything never
// looks like one that did:
//
//   - a level that ticks no new path ends the search (the default tolerance of one
//     such level; `ExploreCoverageOptions.max_tickless_levels` widens this where a caller needs it);
//   - a ceiling on total injected runs ends it regardless of whether a level is still ticking;
//   - reaching a level deeper than there are recorded points to combine ends it too, since no
//     combination of that size can exist at all.
//
// Whichever bound is hit, whatever the checklist still holds unticked is what the caller reads
// back off it: this file returns one of two named errors rather than printing anything itself, so
// a test can assert on the checklist directly and the one caller that runs for real
// (`sim.zig`) is the one place that turns it into output and an exit code.

// What is driven through coverage exploration: one function pointer with a context beside it, the
// same shape `sim.ExploreSubject` already uses. `run` is handed the injector this run was built with (so
// it queues whichever faults this run wants) and the checklist the search is trying to tick off;
// it calls `checklist.tick(name)` for whichever of its own branches this particular run reached,
// whether that is read off a recording log's entries or known directly from the inputs this run
// chose.
pub const CoverageSubject = struct {
    // What `run` reads and writes through: the state a particular subject closes over.
    ctx: *anyopaque,

    // Drives one run of the function under test, given the injector this run was built with and
    // the checklist to tick.
    run: *const fn (ctx: *anyopaque, injector: *Injector, checklist: *Checklist) anyerror!void,
};

// What a search did, for the caller to print. Owned by the caller and written as the search goes,
// rather than returned, so the numbers are there to print whichever way the search ended: a search
// that stopped on one of its bounds is exactly the one whose counts a reader wants.
pub const Counts = struct {
    // Runs that injected at least one fault. The clean pass is not one of these: it fails nothing.
    injected_runs: usize = 0,

    // Faults injected across all of those runs. A level 2 run injects two, so this rises faster
    // than `injected_runs` once the search deepens.
    faults_injected: usize = 0,

    // How many levels the search actually ran, whether it finished them or stopped inside one.
    levels_run: usize = 0,
};

pub const ExploreCoverageOptions = struct {
    // What this search drives.
    subject: CoverageSubject,

    // What this search is trying to tick fully.
    checklist: *Checklist,

    // Ends the search once this many injected runs have happened (the clean pass is not counted:
    // it never fails anything, so it cannot be what makes a run pathological), whatever is still
    // unticked, so one subject that keeps asking for deeper levels cannot spend the whole run.
    max_injected_runs: usize,

    // How many consecutive levels may tick nothing new before the search gives up: `null` (the
    // default) is one, matching "a level that ticks nothing new ends the search"
    // read literally; a caller searching a wider combinatorial space passes a larger tolerance,
    // since such a search can have a genuinely unproductive level with a productive one beyond it.
    max_tickless_levels: ?usize = null,

    // Where to write what this search did, when the caller wants to print it.
    counts: ?*Counts = null,
};

// A level ticked nothing new and the tolerance for that ran out, or the level itself outran how
// many recorded points there are to combine at that size: either way, `options.checklist` still
// names exactly what stayed unticked.
pub fn exploreCoverage(allocator: std.mem.Allocator, options: ExploreCoverageOptions) !void {
    var recorder = Injector.initRecording(allocator);
    defer recorder.deinit();
    try options.subject.run(options.subject.ctx, &recorder, options.checklist);
    if (options.checklist.allTicked()) {
        return;
    }

    const tolerance = options.max_tickless_levels orelse 1;
    var total_runs: usize = 0;
    var tickless_levels: usize = 0;
    var level: usize = 1;

    while (true) {
        if (options.counts) |counts| {
            counts.levels_run = level;
        }
        if (level > recorder.recorded.items.len) {
            return error.CoverageLevelTicklessLimitReached;
        }

        const before_level = options.checklist.untickedCount();

        if (level == 1) {
            for (recorder.recorded.items) |recorded| {
                for (recorded.failures) |failure| {
                    const injections = [_]Injection{.{ .point = recorded.point, .failure = failure.name }};
                    const plan: Plan = .{ .injections = &injections };
                    var injecting = Injector.initReplaying(allocator, plan);
                    defer injecting.deinit();
                    try options.subject.run(options.subject.ctx, &injecting, options.checklist);
                    total_runs += 1;
                    if (options.counts) |counts| {
                        counts.injected_runs += 1;
                        counts.faults_injected += 1;
                    }
                    if (total_runs >= options.max_injected_runs) {
                        return error.CoverageRunCeilingReached;
                    }
                }
            }
        } else {
            const combos = try choosePointCombos(allocator, recorder.recorded.items.len, level);
            defer {
                for (combos) |combo| allocator.free(combo);
                allocator.free(combos);
            }
            for (combos) |combo| {
                try runCombo(allocator, options, recorder.recorded.items, combo, &total_runs);
            }
        }

        if (options.checklist.allTicked()) {
            return;
        }

        if (options.checklist.untickedCount() == before_level) {
            tickless_levels += 1;
            if (tickless_levels >= tolerance) {
                return error.CoverageLevelTicklessLimitReached;
            }
        } else {
            tickless_levels = 0;
        }

        level += 1;
    }
}

// Runs `subject` once per way `combo`'s points can fail together (the cartesian product of each
// chosen point's own declared failures), one simultaneous-fault plan at a time: `combo.len` points
// all fail together in a single run, which is what a level beyond 1 means.
fn runCombo(
    allocator: std.mem.Allocator,
    options: ExploreCoverageOptions,
    points: []const Recorded,
    combo: []const usize,
    total_runs: *usize,
) !void {
    const choice = try allocator.alloc(usize, combo.len);
    defer allocator.free(choice);
    @memset(choice, 0);

    while (true) {
        const injections = try allocator.alloc(Injection, combo.len);
        defer allocator.free(injections);
        for (combo, 0..) |point_index, position| {
            const recorded = points[point_index];
            injections[position] = .{ .point = recorded.point, .failure = recorded.failures[choice[position]].name };
        }
        const plan: Plan = .{ .injections = injections };
        var injecting = Injector.initReplaying(allocator, plan);
        defer injecting.deinit();
        try options.subject.run(options.subject.ctx, &injecting, options.checklist);
        total_runs.* += 1;
        if (options.counts) |counts| {
            counts.injected_runs += 1;
            counts.faults_injected += combo.len;
        }
        if (total_runs.* >= options.max_injected_runs) {
            return error.CoverageRunCeilingReached;
        }

        // Odometer: advances the rightmost choice that still has room, carrying left, so every
        // combination of failures across `combo`'s points is tried exactly once.
        var position = combo.len;
        var wrapped = true;
        while (position > 0) {
            position -= 1;
            const recorded = points[combo[position]];
            choice[position] += 1;
            if (choice[position] < recorded.failures.len) {
                wrapped = false;
                break;
            }
            choice[position] = 0;
        }
        if (wrapped) {
            return;
        }
    }
}

// Every way to choose `size` distinct indices out of `[0, points_len)`, in ascending order within
// each combination: the search never fails the same pair of points twice at a given level.
fn choosePointCombos(allocator: std.mem.Allocator, points_len: usize, size: usize) ![]const []const usize {
    var out: std.ArrayList([]const usize) = .empty;
    errdefer {
        for (out.items) |combo| allocator.free(combo);
        out.deinit(allocator);
    }
    if (size == 0 or size > points_len) {
        return out.toOwnedSlice(allocator);
    }

    const current = try allocator.alloc(usize, size);
    defer allocator.free(current);
    try generateCombos(allocator, points_len, size, 0, current, 0, &out);
    return out.toOwnedSlice(allocator);
}

fn generateCombos(
    allocator: std.mem.Allocator,
    points_len: usize,
    size: usize,
    start: usize,
    current: []usize,
    depth: usize,
    out: *std.ArrayList([]const usize),
) !void {
    if (depth == size) {
        try out.append(allocator, try allocator.dupe(usize, current));
        return;
    }
    var index = start;
    while (index <= points_len - (size - depth)) : (index += 1) {
        current[depth] = index;
        try generateCombos(allocator, points_len, size, index + 1, current, depth + 1, out);
    }
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("coverage_search.test.zig");
}
