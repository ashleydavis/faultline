const std = @import("std");
const rounds = @import("rounds.zig");

// Where these tests write. Under the repository's own tmp directory, which is ignored, the same
// place the other suites keep their fixtures.
const scratch = "tmp/rounds-fixtures";

// A stand-in for kcov: a shell script that takes the arguments the loop gives kcov, writes a file
// into the round directory so the test can see it was run, and exits cleanly. `$3` is the round directory, because the loop passes `--cobertura-only`, the include path,
// then the directory.
const fake_kcov =
    \\#!/usr/bin/env bash
    \\if [ "$1" = "--version" ]; then
    \\    exit 0
    \\fi
    \\echo "ran" > "$3/worker-ran.txt"
    \\exit 0
    \\
;

// A kcov that cannot be run: its `--version` fails.
const broken_kcov =
    \\#!/usr/bin/env bash
    \\exit 1
    \\
;

fn writeScript(io: std.Io, path: []const u8, text: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        try std.Io.Dir.cwd().createDirPath(io, parent);
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text });
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    try file.setPermissions(io, .executable_file);
}

// A subject that plays a script: how many paths each round ticks, in order, and how many functions
// are left after each. It also records what it was asked, so the test can check the loop did each
// thing once per round in the right order.
const Scripted = struct {
    ticks_per_round: []const usize,
    left_per_round: []const usize,
    round: usize = 0,
    remaining_written: usize = 0,
    last_round_dir: [256]u8 = undefined,
    last_round_dir_len: usize = 0,

    fn writeRemaining(ctx: *anyopaque, io: std.Io, path: []const u8) anyerror!usize {
        const self: *Scripted = @ptrCast(@alignCast(ctx));
        self.remaining_written += 1;
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "a.zig\tfirst\t0\n" });
        return if (self.round == 0) 3 else self.left_per_round[self.round - 1];
    }

    fn absorb(ctx: *anyopaque, io: std.Io, round_dir: []const u8, handover_path: []const u8) anyerror!usize {
        const self: *Scripted = @ptrCast(@alignCast(ctx));
        _ = handover_path;
        // The fake kcov left its mark, so the worker was run for this round.
        const marker = try std.fmt.allocPrint(std.testing.allocator, "{s}/worker-ran.txt", .{round_dir});
        defer std.testing.allocator.free(marker);
        const seen = try std.Io.Dir.cwd().readFileAlloc(io, marker, std.testing.allocator, .unlimited);
        defer std.testing.allocator.free(seen);
        @memcpy(self.last_round_dir[0..round_dir.len], round_dir);
        self.last_round_dir_len = round_dir.len;
        const ticked = self.ticks_per_round[self.round];
        self.round += 1;
        return ticked;
    }

    fn remainingCount(ctx: *anyopaque) usize {
        const self: *Scripted = @ptrCast(@alignCast(ctx));
        return self.left_per_round[self.round - 1];
    }

    fn subject(self: *Scripted) rounds.Subject {
        return .{ .ctx = self, .writeRemaining = writeRemaining, .absorb = absorb, .remainingCount = remainingCount };
    }
};

fn optionsFor(kcov: []const u8, out_dir: []const u8) rounds.Options {
    return .{
        .kcov = kcov,
        .out_dir = out_dir,
        .sources_root = "/nowhere/sources",
        .worker = "/nowhere/worker",
        .worker_args = &.{ "--repository", "." },
    };
}

test "a round that ticks every remaining path ends the loop after one round" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    try writeScript(io, scratch ++ "/fake-kcov.sh", fake_kcov);

    var scripted: Scripted = .{ .ticks_per_round = &.{6}, .left_per_round = &.{0} };
    var counts: rounds.Counts = .{};
    try rounds.runRounds(std.testing.allocator, io, optionsFor(scratch ++ "/fake-kcov.sh", scratch ++ "/one"), scripted.subject(), &counts);

    try std.testing.expectEqual(@as(usize, 1), counts.rounds_run);
    try std.testing.expectEqual(@as(usize, 1), scripted.remaining_written);
    try std.testing.expectEqualStrings(scratch ++ "/one/round-1", scripted.last_round_dir[0..scripted.last_round_dir_len]);
}

test "a round that ticks nothing new ends the loop, with the paths still unticked" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    try writeScript(io, scratch ++ "/fake-kcov.sh", fake_kcov);

    // Round one ticks two and leaves one function; round two ticks nothing, so the loop stops there
    // rather than spending every round it has on a path nothing random reaches.
    var scripted: Scripted = .{ .ticks_per_round = &.{ 2, 0, 5 }, .left_per_round = &.{ 1, 1, 1 } };
    var counts: rounds.Counts = .{};
    try rounds.runRounds(std.testing.allocator, io, optionsFor(scratch ++ "/fake-kcov.sh", scratch ++ "/tickless"), scripted.subject(), &counts);

    try std.testing.expectEqual(@as(usize, 1 + rounds.tickless_rounds_tolerance), counts.rounds_run);
    try std.testing.expectEqual(@as(usize, 1), Scripted.remainingCount(&scripted));
}

test "a run whose every round finds one more path stops at the most rounds it allows" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    try writeScript(io, scratch ++ "/fake-kcov.sh", fake_kcov);

    const always_one = [_]usize{1} ** (rounds.max_rounds + 2);
    const always_left = [_]usize{1} ** (rounds.max_rounds + 2);
    var scripted: Scripted = .{ .ticks_per_round = &always_one, .left_per_round = &always_left };
    var counts: rounds.Counts = .{};
    try rounds.runRounds(std.testing.allocator, io, optionsFor(scratch ++ "/fake-kcov.sh", scratch ++ "/bounded"), scripted.subject(), &counts);

    try std.testing.expectEqual(rounds.max_rounds, counts.rounds_run);
    try std.testing.expectEqual(rounds.max_rounds, scripted.remaining_written);
}

test "the loop ends when the last function is ticked, on whichever round that is" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    try writeScript(io, scratch ++ "/fake-kcov.sh", fake_kcov);

    var scripted: Scripted = .{ .ticks_per_round = &.{ 4, 1, 1 }, .left_per_round = &.{ 2, 1, 0 } };
    var counts: rounds.Counts = .{};
    try rounds.runRounds(std.testing.allocator, io, optionsFor(scratch ++ "/fake-kcov.sh", scratch ++ "/three"), scripted.subject(), &counts);

    try std.testing.expectEqual(@as(usize, 3), counts.rounds_run);
    try std.testing.expectEqualStrings(scratch ++ "/three/round-3", scripted.last_round_dir[0..scripted.last_round_dir_len]);
}

test "a worker that exits non-zero fails the run" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    // A kcov whose `--version` works but whose run exits non-zero, which is what a worker that
    // failed looks like from outside.
    try writeScript(io, scratch ++ "/failing-kcov.sh", "#!/usr/bin/env bash\nif [ \"$1\" = \"--version\" ]; then exit 0; fi\nexit 3\n");

    var scripted: Scripted = .{ .ticks_per_round = &.{1}, .left_per_round = &.{1} };
    var counts: rounds.Counts = .{};
    try std.testing.expectError(
        error.WorkerFailed,
        rounds.runRounds(std.testing.allocator, io, optionsFor(scratch ++ "/failing-kcov.sh", scratch ++ "/failing"), scripted.subject(), &counts),
    );
    // The round was counted, so the failure message names the right one.
    try std.testing.expectEqual(@as(usize, 1), counts.rounds_run);
}

test "a kcov that cannot be run is reported as missing before any round" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    try writeScript(io, scratch ++ "/broken-kcov.sh", broken_kcov);

    var scripted: Scripted = .{ .ticks_per_round = &.{1}, .left_per_round = &.{1} };
    var counts: rounds.Counts = .{};
    try std.testing.expectError(
        error.KcovMissing,
        rounds.runRounds(std.testing.allocator, io, optionsFor(scratch ++ "/broken-kcov.sh", scratch ++ "/broken"), scripted.subject(), &counts),
    );
    try std.testing.expectEqual(@as(usize, 0), counts.rounds_run);
    try std.testing.expectEqual(@as(usize, 0), scripted.remaining_written);

    // A name that is on no PATH at all is missing the same way.
    try std.testing.expect(!rounds.isKcovRunnable(io, scratch ++ "/no-such-kcov", null));
}
