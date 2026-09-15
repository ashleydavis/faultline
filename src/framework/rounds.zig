// The loop of rounds a run makes under kcov.
//
// kcov reports what ran only when the process it watched has exited, so a run that wants to stop
// exercising a function once every path of it is ticked has to run in rounds: each round is a
// worker copy of this program run under kcov, given the functions still to exercise; when it exits
// the run reads what kcov and the worker wrote, ticks the checklists, and starts the next round
// with only the functions that still have a path to reach. The loop ends when no function does,
// when a round ticks no new path, or when it has run as many rounds as it allows.
//
// This file knows how to spawn a round and when to stop. What a round means for the checklists is
// the caller's, reached through `Subject`, so the loop can be tested against a worker that is a
// shell script and a subject that counts.

const std = @import("std");
const output = @import("output.zig");

// What the loop asks of its caller. Each function takes the context the caller closed over.
pub const Subject = struct {
    ctx: *anyopaque,

    // Writes the functions still to exercise to `path`, one per line the way the worker reads them,
    // and says how many there are. Every function on the first round.
    writeRemaining: *const fn (ctx: *anyopaque, io: std.Io, path: []const u8) anyerror!usize,

    // Reads what the round left in `round_dir` (kcov's `cov.xml` and the worker's handover file at
    // `handover_path`), ticks whatever they prove, and says how many paths that ticked.
    absorb: *const fn (ctx: *anyopaque, io: std.Io, round_dir: []const u8, handover_path: []const u8) anyerror!usize,

    // How many functions still have an observable path unticked.
    remainingCount: *const fn (ctx: *anyopaque) usize,
};

// How the worker is run.
pub const Options = struct {
    // The kcov binary, a bare name looked up on the PATH or a path.
    kcov: []const u8,

    // Where every round's directory goes. One directory per round under it, so what a round added
    // is readable on its own and kcov never accumulates one round into the next.
    out_dir: []const u8,

    // The directory holding the copies of the repository's sources the worker was compiled from,
    // which is what kcov is told to report on and set breakpoints in. Everything else in the
    // binary, the framework and the standard library, is left alone, which is what keeps a round
    // to the cost of a bare run.
    sources_root: []const u8,

    // The worker binary: this program's own executable.
    worker: []const u8,

    // Arguments every worker round is given after `--worker` and `--round <n>`: the repository,
    // the report path, and whatever narrows the run.
    worker_args: []const []const u8,

    // The environment kcov and the worker run with. Null gives a spawned process the standard
    // library's own default PATH, which is not where a kcov installed under a home directory sits,
    // so a run passes the environment it was started with.
    environ_map: ?*const std.process.Environ.Map = null,
};

// What the loop did, for the summary.
pub const Counts = struct {
    // How many rounds ran.
    rounds_run: usize = 0,
};

// The most rounds a run makes. A function whose branch turns on a value no random draw reaches stays
// unticked however many rounds it is given, and every round after the first costs a kcov start-up
// and the function's full trial count again. Four, because a round that reaches no new path
// already ends the loop, so this only bounds a run where every round still finds one more path:
// three more chances after the first is enough to reach a value drawn one time in a few hundred,
// and a path rarer than that is what a scenario is for.
pub const max_rounds: usize = 4;

// How many rounds in a row may tick no new path before the loop gives up. One: a round draws a
// fresh set of arguments for every remaining function, so a round that reached no new path says the
// next one is expected to reach no new path either, the same rule `coverage_search.zig` applies to
// a level of its search.
pub const tickless_rounds_tolerance: usize = 1;

// The ways the loop ends other than every path being ticked. `KcovMissing` is the one the caller
// turns into a run without kcov; the others end the run.
pub const RoundsError = error{
    KcovMissing,
    WorkerFailed,
} || std.mem.Allocator.Error || anyerror;

// Runs rounds until every path is ticked or a bound is hit. Whatever ended it, `subject`'s
// checklists hold exactly what was reached.
pub fn runRounds(allocator: std.mem.Allocator, io: std.Io, options: Options, subject: Subject, counts: *Counts) RoundsError!void {
    if (!isKcovRunnable(io, options.kcov, options.environ_map)) {
        return error.KcovMissing;
    }

    var tickless_rounds: usize = 0;
    var round: usize = 1;
    while (round <= max_rounds) : (round += 1) {
        counts.rounds_run = round;

        const round_dir = try std.fmt.allocPrint(allocator, "{s}/round-{d}", .{ options.out_dir, round });
        defer allocator.free(round_dir);
        try std.Io.Dir.cwd().createDirPath(io, round_dir);

        const remaining_path = try std.fmt.allocPrint(allocator, "{s}/remaining.txt", .{round_dir});
        defer allocator.free(remaining_path);
        const handover_path = try std.fmt.allocPrint(allocator, "{s}/handover.txt", .{round_dir});
        defer allocator.free(handover_path);

        const remaining = try subject.writeRemaining(subject.ctx, io, remaining_path);
        output.print("  Round {d}: exercising {d} function{s} under kcov.\n", .{ round, remaining, plural(remaining) });

        try runWorker(allocator, io, options, round, round_dir, remaining_path, handover_path);

        const ticked = try subject.absorb(subject.ctx, io, round_dir, handover_path);
        const left = subject.remainingCount(subject.ctx);
        output.print("  Round {d} ticked {d} path{s}; {d} function{s} still {s} a path to reach.\n", .{
            round,
            ticked,
            plural(ticked),
            left,
            plural(left),
            if (left == 1) "has" else "have",
        });

        if (left == 0) {
            return;
        }
        if (ticked == 0) {
            tickless_rounds += 1;
            if (tickless_rounds >= tickless_rounds_tolerance) {
                return;
            }
        } else {
            tickless_rounds = 0;
        }
    }
}

// Whether `kcov` can be run at all: it is started with `--version` and has to exit cleanly. A bare
// name is looked up on the PATH the way a shell would.
pub fn isKcovRunnable(io: std.Io, kcov: []const u8, environ_map: ?*const std.process.Environ.Map) bool {
    var child = std.process.spawn(io, .{
        .argv = &.{ kcov, "--version" },
        .stdout = .ignore,
        .stderr = .ignore,
        .environ_map = environ_map,
    }) catch return false;
    const term = child.wait(io) catch return false;
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

// One round: kcov around the worker, with the worker's output going straight to the terminal so a
// round reads the way the run always has. A worker that exits non-zero ends the run, with what it
// printed already on the terminal above.
fn runWorker(
    allocator: std.mem.Allocator,
    io: std.Io,
    options: Options,
    round: usize,
    round_dir: []const u8,
    remaining_path: []const u8,
    handover_path: []const u8,
) !void {
    const include = try std.fmt.allocPrint(allocator, "--include-path={s}", .{options.sources_root});
    defer allocator.free(include);
    const round_text = try std.fmt.allocPrint(allocator, "{d}", .{round});
    defer allocator.free(round_text);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &.{
        options.kcov,
        "--cobertura-only",
        include,
        round_dir,
        options.worker,
        "--worker",
        "--round",
        round_text,
        "--remaining",
        remaining_path,
        "--handover",
        handover_path,
    });
    try argv.appendSlice(allocator, options.worker_args);

    var child = try std.process.spawn(io, .{ .argv = argv.items, .environ_map = options.environ_map });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                output.print("The run failed in round {d}; what it printed is above.\n", .{round});
                return error.WorkerFailed;
            }
        },
        else => {
            output.print("The run was killed in round {d}; what it printed is above.\n", .{round});
            return error.WorkerFailed;
        },
    }
}

fn plural(count: usize) []const u8 {
    return if (count == 1) "" else "s";
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("rounds.test.zig");
}
