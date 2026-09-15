// Runs the automatic runner in a child process so a call that crashes or hangs costs one restart
// rather than the whole run.
//
// Calling a function with everything its parameter types allow reaches inputs the function was
// never written for: a count larger than the range it indexes, a float with no integer part, an
// empty slice it dereferences, a duration measured in centuries. None of that is in a signature, so
// nothing can avoid it in advance. What can be done is to make it survivable: the child streams
// each annotation as it records it, the parent keeps what arrived, and a call that killed the child
// or stopped producing anything is stepped over and never tried again.
//
// Nothing here names a package's own types. What crosses the pipe is the call's own index and the
// names the code annotated, both plain bytes.

const std = @import("std");
const output_mod = @import("output.zig");

// How long a single call may produce nothing before it is taken to be stuck.
//
// Nothing the run hands a function blocks: the network refuses at once, a wait returns at once, the
// writer is memory and the allocator is an arena. So the only thing this can catch is a loop in the
// code under test that does not end, and the limit is set far above what a call costs on a machine
// running several suites at once.
//
// **It has to be far above, because stepping over a call changes what the run covers.** At two
// seconds, a run alongside the other suites lost blocks of calls to scheduling gaps rather than to
// anything being stuck, and came back red on paths that a run on an idle machine had covered:
// coverage that depends on how busy the machine is is a flaky test, which this repository does not
// have. Found on 2026-09-11, when `zig build sim` passed on its own and failed inside
// `test:everything` minutes later.
pub const stall_limit_ms = 30_000;

// How much processor time one call may use before it is taken to be going round forever.
//
// This is what actually catches a loop that does not end, and the limit above is only the backstop
// for a child that has stopped without using any. Processor time is the right measure because it is
// the one a busy machine does not change: a call given thirty seconds of wall clock can lose most
// of it to other suites running beside it, which is how a two-second wall limit came to drop calls
// that were not stuck and made coverage depend on how busy the machine was.
//
// Five seconds is about a thousand times what the slowest call that finishes uses.
pub const call_processor_limit_seconds = 5;

// What the child exits with when that limit fires. The parent tells this from a crash by reading
// the exit status: a crash steps over one call, while a call going round forever drops the rest of
// the block it was in, since the next value is likely to do the same thing.
const stalled_exit_code = 102;

// What the parent tells the child, and what the child reports back. The child is forked, so it
// reads this straight out of the address space it was copied from: nothing is serialised, and the
// parent changes it between restarts.
pub const Plan = struct {
    // The call to resume at. Everything before it either ran or was stepped over already.
    start: usize = 0,

    // The calls that killed a child, which no later attempt tries again.
    skipped: []const usize = &.{},

    // The calls that hung, whose whole block a caller drops.
    stalled: []const usize = &.{},

    pub fn isSkipped(self: Plan, index: usize) bool {
        for (self.skipped) |entry| {
            if (entry == index) {
                return true;
            }
        }
        return false;
    }

    // Whether anything in this range hung, so a caller can drop the whole block rather than pay
    // the stall limit again for the next value that also hangs.
    pub fn stalledWithin(self: Plan, from: usize, until: usize) bool {
        for (self.stalled) |entry| {
            if (entry >= from and entry < until) {
                return true;
            }
        }
        return false;
    }

    // How many calls in this range were stepped over. Every one of them cost a restart, and a
    // restart replays the walk from the beginning, so a caller stops paying once a block has shown
    // it is mostly outside what the code accepts.
    pub fn skippedCountWithin(self: Plan, from: usize, until: usize) usize {
        var total: usize = 0;
        for (self.skipped) |entry| {
            if (entry >= from and entry < until) {
                total += 1;
            }
        }
        return total;
    }
};

// One line of what a child says: which call it is about to make, one annotation it recorded, which
// function it has moved on to, or that it reached the end.
pub const line_at = 'A';
pub const line_name = 'N';
pub const line_done = 'D';
pub const line_function = 'F';

// What one attempt produced: the annotations that arrived, how far the child got, and whether it
// finished or died.
pub const Attempt = struct {
    last_index: usize,
    finished: bool,
    killed: bool,

    // Whether the child stopped saying anything rather than dying. The two are stepped over
    // differently: a call that crashed costs one restart, while a call that hangs costs the stall
    // limit, so a caller drops the whole block it was in rather than paying that again for the
    // next value that also hangs.
    stalled: bool = false,
};

const linux = std.os.linux;

// Where a child writes what it is doing. Every line is flushed as it is written, because what the
// parent keeps after a crash is exactly what reached the pipe before it.
pub const Emitter = struct {
    // Nothing. What a child says goes into memory both processes can see, so there is no handle to
    // carry and no copy of this that can be writing somewhere else.

    pub fn at(self: Emitter, index: usize) void {
        _ = self;
        var room: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&room, "{c}{d}\n", .{ line_at, index }) catch return;
        put(text);
    }

    // The name, and which of the caller's own subjects it belongs to. The subject crosses as a
    // number rather than a string, so nothing here has to know what a subject is or own its text.
    pub fn name(self: Emitter, subject: usize, value: []const u8) void {
        _ = self;
        var room: [512]u8 = undefined;
        const text = std.fmt.bufPrint(&room, "{c}{d}\t{s}\n", .{ line_name, subject, value }) catch return;
        put(text);
    }

    // Which function the calls after this one belong to, so the parent can say where a run spent
    // its time. The child cannot time anything itself: it is restarted whenever a call kills it,
    // and what it had collected dies with it.
    pub fn function(self: Emitter, file: []const u8, value: []const u8) void {
        _ = self;
        var room: [512]u8 = undefined;
        const text = std.fmt.bufPrint(&room, "{c}{s}\t{s}\n", .{ line_function, file, value }) catch return;
        put(text);
    }

    pub fn done(self: Emitter) void {
        _ = self;
        put(&[_]u8{ line_done, '\n' });
    }
};

// What a child says, in memory both processes can see.
//
// Mapped shared before the fork, so the child writes into it with no system call at all and the
// parent reads it as it goes. A run records millions of names, and a write each made the calls into
// the kernel the larger part of what a run cost. Shared rather than the child's own memory, because
// the point of a child is that it may die: what it said has to outlive it.
const shared_bytes = 1 << 22;

const Shared = extern struct {
    // How much the child has written, counted from the start of the run and never wrapped. Only the
    // child writes this.
    written: usize,

    // How much the parent has taken. Only the parent writes this.
    taken: usize,

    // The bytes themselves, used as a ring: a position in the two counts above is `% room.len`.
    room: [shared_bytes]u8,
};

var shared: ?*Shared = null;

// Maps the region, once, before the first fork. Both processes then have it: a mapping made before
// a fork is shared with everything forked after it.
fn openShared() !*Shared {
    if (shared) |already| {
        return already;
    }
    const mapped = linux.mmap(
        null,
        @sizeOf(Shared),
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .SHARED, .ANONYMOUS = true },
        -1,
        0,
    );
    if (linux.errno(mapped) != .SUCCESS) {
        return error.SimCannotShareMemory;
    }
    const region: *Shared = @ptrFromInt(mapped);
    region.written = 0;
    region.taken = 0;
    shared = region;
    return region;
}

// Writes one line where the parent can read it. No system call: this is a copy into memory the two
// processes share.
fn put(bytes: []const u8) void {
    const region = shared orelse return;
    // The parent reads as the child writes, so the ring only fills when the parent is behind. Giving
    // up the processor rather than spinning is the only call into the kernel here, and it happens
    // when there is nothing else to do anyway.
    while (region.written - region.taken + bytes.len > region.room.len) {
        _ = linux.sched_yield();
    }
    var at = region.written % region.room.len;
    for (bytes) |byte| {
        region.room[at] = byte;
        at = (at + 1) % region.room.len;
    }
    // Written last, so the parent never reads a position the bytes have not reached.
    @atomicStore(usize, &region.written, region.written + bytes.len, .release);
}

// Takes what the child has written since the last time, up to a block at once, into `pending`.
//
// A block rather than everything, so what is being parsed stays small: the parser takes a line off
// the front of it, and a front that is megabytes long is moved megabytes at a time.
const take_at_once = 1 << 16;

fn take(region: *Shared, pending: *std.ArrayList(u8), allocator: std.mem.Allocator) !bool {
    const written = @atomicLoad(usize, &region.written, .acquire);
    if (written == region.taken) {
        return false;
    }
    const wanted = @min(written - region.taken, take_at_once);
    const from = region.taken % region.room.len;
    if (from + wanted <= region.room.len) {
        try pending.appendSlice(allocator, region.room[from..][0..wanted]);
    } else {
        const to_the_end = region.room.len - from;
        try pending.appendSlice(allocator, region.room[from..][0..to_the_end]);
        try pending.appendSlice(allocator, region.room[0 .. wanted - to_the_end]);
    }
    region.taken += wanted;
    return true;
}

// Runs `body` in a child and keeps whatever it managed to say. `body` is handed the plan it is
// working to and somewhere to report; it never returns, because the child leaves through `exit`
// rather than unwinding back into a parent's `defer`s and allocator checks.
pub fn attempt(
    plan: Plan,
    comptime body: fn (plan: Plan, out: Emitter) void,
    collected: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !Attempt {
    const region = try openShared();
    // Each attempt starts where the last one left off rather than at nothing, so the two counts stay
    // in step across the restarts a run makes.
    region.taken = region.written;

    const pid = linux.fork();
    if (linux.errno(pid) != .SUCCESS) {
        return error.SimCannotFork;
    }

    if (pid == 0) {
        in_child = true;
        silenceChildErrors();
        letCrashesBeCrashes();
        watchProcessorTime();
        body(plan, .{});
        linux.exit(0);
    }

    return readChild(@intCast(pid), region, plan, collected, allocator);
}

// Whether this process is one of the forked children. Set once, immediately after the fork, and
// read by the panic handler, which has to behave differently in the two: a crash in a child is the
// ordinary case and a crash in the parent is a bug in the run itself.
var in_child = false;

// What a panic does. A child leaves at once, without a message and without a stack trace, because
// building one costs about a second: measured on 2026-09-11 at 1.08s per panic in ReleaseSafe, with
// the message already going to /dev/null, which came to the larger part of a four-minute run. There
// is nothing to read either way, since the child's error output goes nowhere.
//
// The parent panics the ordinary way. A crash there is a defect in the framework rather than a call
// landing outside what a function accepts, and the message and trace are the whole diagnosis.
//
// The exit is `exit_group` rather than `exit`: a child holds a thread pool, and leaving only the
// panicking thread would hang the parent waiting for a process that has not ended.
pub fn panicQuietlyInChild(message: []const u8, first_trace_address: ?usize) noreturn {
    if (in_child) {
        linux.exit_group(101);
    }
    std.debug.defaultPanic(message, first_trace_address);
}

// Makes a crash cost nothing but the restart.
//
// A child dies often here, because a call built from a signature alone reaches inputs the function
// was never written for. Two things on this machine turn each of those deaths into about a second,
// and a run steps over a hundred and fifty calls, so between them they were the larger part of it.
//
// The core dump is the expensive one. `/proc/sys/kernel/core_pattern` pipes to a crash reporter, and
// the kernel runs it whatever the core size limit is set to, so every crash paid for a copy of the
// child's memory being written to a program that reads it and throws it away. Measured on
// 2026-09-11: 1.07s per crash with it, 0.4ms without.
//
// The signal handlers are the other. The standard library installs its own for the crash signals,
// and each resolves a stack trace before it exits, which nothing here reads: the child's error
// output goes nowhere.
//
// Both are answered the same way: the child catches each crash signal in a handler that does
// nothing but leave. A process that leaves is never dumped, so the reporter never runs, and no
// trace is built. The parent learns about the crash from the child ending without saying it was
// done, exactly as it did when the child was killed by the signal.
//
// It used to say the child was not to be dumped instead (`PR_SET_DUMPABLE`), and leave the signals
// at their defaults. That flag also tells the kernel to refuse a tracer's reads and writes into the
// child, and kcov is a tracer: under it a breakpoint the child hit could never be cleared, so the
// child trapped on the same instruction millions of times until the parent gave up on it. Measured
// on 2026-09-15 against the if-else example: 63s and two calls stepped over as stuck, against
// under a second bare.
//
// Only the child does this. In the parent a crash means a defect in the run itself, and the dump and
// the trace are how it is found.
fn letCrashesBeCrashes() void {
    // The handler runs on a stack of its own, because one of the crashes it catches is running out
    // of stack, and a handler with nowhere to run is not run: the kernel kills the process the
    // default way, which is the dump this exists to avoid.
    const alternate: linux.stack_t = .{
        .sp = &crash_stack,
        .flags = 0,
        .size = crash_stack.len,
    };
    _ = linux.sigaltstack(&alternate, null);

    const leaving: linux.Sigaction = .{
        .handler = .{ .handler = &leaveOnCrash },
        .mask = linux.sigemptyset(),
        .flags = linux.SA.ONSTACK,
    };
    // `ABRT` is on the list because `std.process.abort` raises it, and an abort is dumped the same
    // way a segfault is.
    const crashes = [_]linux.SIG{ .SEGV, .BUS, .ILL, .FPE, .TRAP, .ABRT };
    for (crashes) |signal| {
        _ = linux.sigaction(signal, &leaving, null);
    }
}

// Where the crash handler runs. The size is the standard library's own recommended signal stack,
// which is enough for a handler that makes one system call and nothing else. Static rather than
// allocated, because the child is forked from a parent that never runs the handler, and a copy per
// child costs nothing until the child writes to it.
var crash_stack: [linux.SIGSTKSZ]u8 align(16) = undefined;

// What the child exits with when a call crashed it. Distinct from `stalled_exit_code` so the
// parent's reading of the two stays apart, and non-zero so a child that crashed is never taken
// for one that finished.
const crashed_exit_code = 101;

fn leaveOnCrash(_: linux.SIG) callconv(.c) void {
    linux.exit_group(crashed_exit_code);
}

// Arms the signal a call going round forever ends on. Its default is to kill the process, which
// would read to the parent as a crash, so the child catches it and leaves with a status saying what
// happened instead.
fn watchProcessorTime() void {
    const ending: linux.Sigaction = .{
        .handler = .{ .handler = &leaveOnProcessorTime },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    _ = linux.sigaction(.VTALRM, &ending, null);
}

fn leaveOnProcessorTime(_: linux.SIG) callconv(.c) void {
    linux.exit_group(stalled_exit_code);
}

// Starts and stops the processor-time limit around one call. Called by whatever is exercising, because
// only it knows where one call ends and the next begins.
pub fn startCallClock() void {
    setCallClock(call_processor_limit_seconds);
}

pub fn stopCallClock() void {
    setCallClock(0);
}

fn setCallClock(seconds: isize) void {
    const when: linux.itimerspec = .{
        .it_interval = .{ .sec = 0, .nsec = 0 },
        .it_value = .{ .sec = seconds, .nsec = 0 },
    };
    _ = linux.setitimer(@intFromEnum(linux.ITIMER.VIRTUAL), &when, null);
}

// A child that crashes is the ordinary case here, not a fault to report: the call was outside what
// the function accepts, which no signature said and nothing could have avoided. Its panic and stack
// trace would bury the run's own output under a page of noise per crash, so the child's error
// output goes nowhere. What the run has to say about a crash is that the call was stepped over,
// and it says that itself.
fn silenceChildErrors() void {
    const nowhere = linux.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0);
    if (linux.errno(nowhere) != .SUCCESS) {
        return;
    }
    _ = linux.dup2(@intCast(nowhere), 2);
    _ = linux.close(@intCast(nowhere));
}

// Reads what the child says until it finishes, dies, or stops saying anything for long enough to
// be taken as stuck. What arrived is kept either way: a call that crashed still annotated whatever
// it reached before it did.
fn readChild(
    pid: i32,
    region: *Shared,
    plan: Plan,
    collected: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !Attempt {
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(allocator);

    var found: Attempt = .{ .last_index = plan.start, .finished = false, .killed = false };
    var status: u32 = 0;
    var reaped = false;
    var quiet_ms: usize = 0;

    while (true) {
        const said_something = try take(region, &pending, allocator);
        var read: usize = 0;
        while (std.mem.indexOfScalar(u8, pending.items[read..], '\n')) |end| {
            try takeLine(pending.items[read..][0..end], &found, collected, allocator);
            read += end + 1;
        }
        if (read != 0) {
            pending.replaceRange(allocator, 0, read, &.{}) catch unreachable;
        }
        if (found.finished) {
            break;
        }
        if (said_something) {
            quiet_ms = 0;
            continue;
        }
        // Nothing new. The child has either ended, or is working, or is stuck, and the three are
        // told apart by whether it is still there and how long it has been quiet.
        if (reaped) {
            found.killed = true;
            break;
        }
        const answer = linux.wait4(pid, &status, linux.W.NOHANG, null);
        if (linux.errno(answer) == .SUCCESS and answer != 0) {
            reaped = true;
            continue;
        }
        var a_moment = linux.timespec{ .sec = 0, .nsec = 1_000_000 };
        _ = linux.nanosleep(&a_moment, null);
        quiet_ms += 1;
        if (quiet_ms >= stall_limit_ms) {
            // Nothing for the whole limit, so the call named by `last_index` is not coming back.
            found.killed = true;
            found.stalled = true;
            break;
        }
    }

    // Whatever was being timed ends here, whether the child finished or was killed: the next
    // attempt says which function it is on before its first call, so nothing is left running.
    startTiming("", allocator) catch {};

    if (found.killed and !reaped) {
        _ = linux.kill(pid, .KILL);
    }
    if (!reaped) {
        _ = linux.wait4(pid, &status, 0, null);
    }
    if (!found.finished and !found.killed) {
        found.killed = true;
    }

    // A child that left on the processor-time limit said nothing on its way out, so the loop above
    // ended without anything to say it was stuck. Its exit status is where that is written.
    if (leftOnProcessorTime(status)) {
        found.killed = true;
        found.stalled = true;
    }
    return found;
}

fn takeLine(
    line: []const u8,
    found: *Attempt,
    collected: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !void {
    if (line.len == 0) {
        return;
    }
    switch (line[0]) {
        line_at => {
            found.last_index = std.fmt.parseInt(usize, line[1..], 10) catch found.last_index;
            timing_calls += 1;
            reportProgress(found.last_index);
        },
        line_name => try collected.append(allocator, try allocator.dupe(u8, line[1..])),
        line_function => try startTiming(line[1..], allocator),
        line_done => found.finished = true,
        else => {},
    }
}

// Whether a child ended by exiting with the status the processor-time limit uses, rather than by
// crashing or being killed. `wait4` packs both into one word: the low byte says which, and for an
// ordinary exit the byte above it carries the status.
fn leftOnProcessorTime(status: u32) bool {
    const exited = status & 0x7f == 0;
    return exited and (status >> 8) & 0xff == stalled_exit_code;
}

// How many calls were stepped over for producing nothing rather than for crashing. A crash is
// ordinary: a call assembled from a signature alone reaches inputs the function was never written
// for. A stall is not, since nothing the run hands over blocks, so a reader has to be able to tell
// the two apart in what a run reports.
var calls_stalled: usize = 0;

pub fn stalledCount() usize {
    return calls_stalled;
}

// How long the exercising spent in one function, named the way the child named it: the module's own
// index and the function's name, separated by a tab. Kept here rather than in the run above,
// because only the parent has a clock that survives a child being restarted.
pub const Timing = struct {
    // "<file>\t<function name>", copied from the line the child sent, which is exactly how the
    // report names a function.
    key: []const u8,

    // How long the parent read that function's calls for, added up across every restart.
    nanos: u64,

    // How many calls that function was given, added up the same way. A function reaching every
    // path it has in the first fifty calls and then being called six thousand times is not visible
    // in a duration, which is why this is reported beside one.
    calls: usize,
};

var timings: std.ArrayList(Timing) = .empty;
var timing_key: ?[]const u8 = null;
var timing_started_ns: u64 = 0;
var timing_calls: usize = 0;

// The monotonic clock, read straight from the kernel. `std.Io` is how the rest of this repository
// reads a clock, and this file cannot: it is the one place that forks, waits and polls through
// `std.os.linux` directly, and a child's restart cycle runs underneath any `Io` a caller holds.
fn nowNs() u64 {
    var when: linux.timespec = undefined;
    if (linux.errno(linux.clock_gettime(.MONOTONIC, &when)) != .SUCCESS) {
        return 0;
    }
    return @as(u64, @intCast(when.sec)) * std.time.ns_per_s + @as(u64, @intCast(when.nsec));
}

// Closes off whatever was being timed and starts timing `key`. Called every time the child says it
// has moved on, and once more when the child stops, so the last function is not left out.
fn startTiming(key: []const u8, allocator: std.mem.Allocator) !void {
    const now = nowNs();
    if (timing_key) |previous| {
        try addTiming(previous, now - timing_started_ns, timing_calls, allocator);
        allocator.free(previous);
    }
    timing_key = if (key.len == 0) null else try allocator.dupe(u8, key);
    timing_started_ns = now;
    timing_calls = 0;
}

fn addTiming(key: []const u8, nanos: u64, calls: usize, allocator: std.mem.Allocator) !void {
    for (timings.items) |*held| {
        if (std.mem.eql(u8, held.key, key)) {
            held.nanos += nanos;
            held.calls += calls;
            return;
        }
    }
    try timings.append(allocator, .{ .key = try allocator.dupe(u8, key), .nanos = nanos, .calls = calls });
}

// What every function's exercising cost, for whoever prints the report. The order is the order the
// functions were first reached.
pub fn everyTiming() []const Timing {
    return timings.items;
}

// Adds what a worker round timed to this process's own table, so a run whose exercising happened in
// other processes reports it the same way. Keyed the way the child names a function.
pub fn addTimingFrom(file: []const u8, function_name: []const u8, nanos: u64, calls: usize, allocator: std.mem.Allocator) !void {
    const key = try std.fmt.allocPrint(allocator, "{s}\t{s}", .{ file, function_name });
    defer allocator.free(key);
    try addTiming(key, nanos, calls, allocator);
}

// Adds a worker round's stalled calls to this process's own count, for the same reason.
pub fn addStalled(count: usize) void {
    calls_stalled += count;
}

// How long one function's exercising took, for whoever is printing a line about it. Zero for a
// function nothing exercised, which is what a scenario-only function reads as.
pub fn timingFor(file: []const u8, function_name: []const u8) u64 {
    const held = timingOf(file, function_name) orelse return 0;
    return held.nanos;
}

// How many calls one function was given, for the same reader. Zero for a function nothing exercised.
pub fn callsFor(file: []const u8, function_name: []const u8) usize {
    const held = timingOf(file, function_name) orelse return 0;
    return held.calls;
}

fn timingOf(file: []const u8, function_name: []const u8) ?Timing {
    for (timings.items) |held| {
        const tab = std.mem.indexOfScalar(u8, held.key, '\t') orelse continue;
        if (std.mem.eql(u8, held.key[0..tab], file) and std.mem.eql(u8, held.key[tab + 1 ..], function_name)) {
            return held;
        }
    }
    return null;
}

pub fn freeTimings(allocator: std.mem.Allocator) void {
    for (timings.items) |held| allocator.free(held.key);
    timings.deinit(allocator);
    timings = .empty;
    if (timing_key) |held| {
        allocator.free(held);
    }
    timing_key = null;
    timing_calls = 0;
    progress_started_ns = 0;
    progress_last_ns = 0;
}

// How often a run says how far it has got. A run takes minutes and its whole report comes at the
// end, so without this it cannot be told from a run that has hung.
//
// Half a second, and measured in time rather than in calls, because the line is rewritten in place
// rather than scrolled: it has to keep up with a run that is moving and stay quiet on one that is
// not. Counting calls, which is what this did until 2026-09-15, tied the update rate to how fast
// the calls happened to be: 80 lines in a two minute run, and nothing at all for the length of one
// slow function, which is the case the line exists for.
const progress_every_ns = 500 * std.time.ns_per_ms;

// When the run's first progress line was written, and when its last one was. Both are wall clock,
// read only to decide when to print and what to say the elapsed time is. Nothing in the simulation
// is decided by either.
var progress_started_ns: u64 = 0;
var progress_last_ns: u64 = 0;

// Whether anybody is watching. These lines exist so a person can tell a slow run from a hung one,
// which nothing captured to a file needs: there they are fifty lines of noise around the report.
// Set once, from whether the run's own output is going to a terminal.
pub var progress_is_watched: bool = true;

fn reportProgress(index: usize) void {
    if (!progress_is_watched) {
        return;
    }

    const now = nowNs();
    if (progress_started_ns == 0) {
        progress_started_ns = now;
    }
    if (now - progress_last_ns < progress_every_ns) {
        return;
    }
    progress_last_ns = now;

    var elapsed_buffer: [32]u8 = undefined;
    output_mod.printProgress("  Exercised {d} call{s} in {s}.", .{
        index,
        if (index == 1) "" else "s",
        elapsedText(&elapsed_buffer, now - progress_started_ns),
    });
}

// How long the run has been going, as the fragment the progress line reads it back as: "9s" for
// under a minute, "2m 14s" above it. The buffer is the caller's, so this allocates nothing on a
// path that runs twice a second.
pub fn elapsedText(buffer: []u8, nanos: u64) []const u8 {
    const seconds = nanos / std.time.ns_per_s;
    if (seconds < 60) {
        return std.fmt.bufPrint(buffer, "{d}s", .{seconds}) catch "a while";
    }
    return std.fmt.bufPrint(buffer, "{d}m {d}s", .{ seconds / 60, seconds % 60 }) catch "a while";
}

// Runs `body` as many times as it takes: every time a child dies or stalls, the call it was on is
// stepped over and the next attempt resumes after it. Returns when a child reaches the end, and
// the annotations from every attempt are in `collected`.
pub fn exerciseUntilDone(
    comptime body: fn (plan: Plan, out: Emitter) void,
    collected: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) ![]const usize {
    var skipped: std.ArrayList(usize) = .empty;
    errdefer skipped.deinit(allocator);
    var stalled: std.ArrayList(usize) = .empty;
    defer stalled.deinit(allocator);

    var start: usize = 0;
    while (true) {
        const plan: Plan = .{ .start = start, .skipped = skipped.items, .stalled = stalled.items };
        const found = try attempt(plan, body, collected, allocator);
        if (found.finished) {
            break;
        }
        try skipped.append(allocator, found.last_index);
        if (found.stalled) {
            try stalled.append(allocator, found.last_index);
            calls_stalled += 1;
        }
        start = found.last_index + 1;
    }

    return skipped.toOwnedSlice(allocator);
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("isolate.test.zig");
}
