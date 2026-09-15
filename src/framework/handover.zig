// What a worker round hands back to the run that spawned it, and what that run hands the worker.
//
// A round runs in a process of its own under kcov, so what it annotated, how long each function's
// calls took and how many calls were stepped over all die with it unless they are written down.
// They are written to one file, one record per line, tab-separated, with a letter first saying what
// the record is: `A` an annotation, `T` a function's timing, `C` the round's counts. The list of
// functions a round is to exercise goes the other way in a file of the same style, one `file`,
// `function` and `occurrence` per line.
//
// Plain text rather than anything structured, because both ends are this same program and the only
// reader is `readHandover` below.

const std = @import("std");

// One annotation the worker recorded, the way `sim.Annotated` holds it, without importing `sim`.
pub const Annotation = struct {
    // The module file it was emitted under, as the build recorded it.
    module: []const u8,

    // The annotation's own name.
    name: []const u8,

    // Whether the runner reached it from a function's own types rather than a scenario.
    from_runner: bool,
};

// How long one function's calls took and how many there were, as the worker's parent timed them.
pub const Timing = struct {
    // The file and function, as the report names them.
    file: []const u8,
    function: []const u8,

    // Wall-clock nanoseconds spent reading that function's calls.
    nanos: u64,

    // How many calls it was given.
    calls: usize,
};

// The round's totals, which the report prints and which live nowhere else once the worker exits.
pub const Counts = struct {
    // How many exploration runs injected a fault.
    faults_injected: usize = 0,

    // How many calls were stepped over, for crashing or for stalling.
    stepped_over: usize = 0,

    // How many of those stalled rather than crashed.
    stalled: usize = 0,
};

// One function a round is to exercise, named the way the run names it.
pub const Function = struct {
    file: []const u8,
    function: []const u8,
    occurrence: usize,
};

// Everything a worker wrote, read back with every string owned by `allocator`.
pub const Handover = struct {
    allocator: std.mem.Allocator,
    annotations: []Annotation,
    timings: []Timing,
    counts: Counts,

    pub fn deinit(self: *Handover) void {
        for (self.annotations) |entry| {
            self.allocator.free(entry.module);
            self.allocator.free(entry.name);
        }
        self.allocator.free(self.annotations);
        for (self.timings) |entry| {
            self.allocator.free(entry.file);
            self.allocator.free(entry.function);
        }
        self.allocator.free(self.timings);
    }
};

// Writes what a round did to `path`, making the directory it sits in.
pub fn writeHandover(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    annotations: []const Annotation,
    timings: []const Timing,
    counts: Counts,
) !void {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    const writer = &text.writer;
    for (annotations) |entry| {
        try writer.print("A\t{s}\t{s}\t{d}\n", .{ entry.module, entry.name, @intFromBool(entry.from_runner) });
    }
    for (timings) |entry| {
        try writer.print("T\t{s}\t{s}\t{d}\t{d}\n", .{ entry.file, entry.function, entry.nanos, entry.calls });
    }
    try writer.print("C\t{d}\t{d}\t{d}\n", .{ counts.faults_injected, counts.stepped_over, counts.stalled });
    try writeWholeFile(io, path, text.written());
}

// Reads a file `writeHandover` wrote. A line that does not parse is passed over rather than failing
// the round: what was written is this program's own, so a malformed line is a defect to fix here,
// and losing one record is better than losing the round.
pub fn readHandover(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !Handover {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    defer allocator.free(text);

    var annotations: std.ArrayList(Annotation) = .empty;
    errdefer {
        for (annotations.items) |entry| {
            allocator.free(entry.module);
            allocator.free(entry.name);
        }
        annotations.deinit(allocator);
    }
    var timings: std.ArrayList(Timing) = .empty;
    errdefer {
        for (timings.items) |entry| {
            allocator.free(entry.file);
            allocator.free(entry.function);
        }
        timings.deinit(allocator);
    }
    var counts: Counts = .{};

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len < 2 or line[1] != '\t') {
            continue;
        }
        var fields = std.mem.splitScalar(u8, line[2..], '\t');
        switch (line[0]) {
            'A' => {
                const module = fields.next() orelse continue;
                const name = fields.next() orelse continue;
                const from_runner = fields.next() orelse continue;
                const owned_module = try allocator.dupe(u8, module);
                errdefer allocator.free(owned_module);
                const owned_name = try allocator.dupe(u8, name);
                errdefer allocator.free(owned_name);
                try annotations.append(allocator, .{
                    .module = owned_module,
                    .name = owned_name,
                    .from_runner = std.mem.eql(u8, from_runner, "1"),
                });
            },
            'T' => {
                const file = fields.next() orelse continue;
                const function = fields.next() orelse continue;
                const nanos = std.fmt.parseInt(u64, fields.next() orelse continue, 10) catch continue;
                const calls = std.fmt.parseInt(usize, fields.next() orelse continue, 10) catch continue;
                const owned_file = try allocator.dupe(u8, file);
                errdefer allocator.free(owned_file);
                const owned_function = try allocator.dupe(u8, function);
                errdefer allocator.free(owned_function);
                try timings.append(allocator, .{ .file = owned_file, .function = owned_function, .nanos = nanos, .calls = calls });
            },
            'C' => {
                counts.faults_injected = std.fmt.parseInt(usize, fields.next() orelse continue, 10) catch continue;
                counts.stepped_over = std.fmt.parseInt(usize, fields.next() orelse continue, 10) catch continue;
                counts.stalled = std.fmt.parseInt(usize, fields.next() orelse continue, 10) catch continue;
            },
            else => {},
        }
    }

    return .{
        .allocator = allocator,
        .annotations = try annotations.toOwnedSlice(allocator),
        .timings = try timings.toOwnedSlice(allocator),
        .counts = counts,
    };
}

// Writes the functions a round is to exercise to `path`, making the directory it sits in.
pub fn writeRemaining(allocator: std.mem.Allocator, io: std.Io, path: []const u8, functions: []const Function) !void {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    for (functions) |entry| {
        try text.writer.print("{s}\t{s}\t{d}\n", .{ entry.file, entry.function, entry.occurrence });
    }
    try writeWholeFile(io, path, text.written());
}

// Reads a file `writeRemaining` wrote. The caller owns what comes back, and `freeRemaining`
// releases it.
pub fn readRemaining(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]Function {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    defer allocator.free(text);

    var functions: std.ArrayList(Function) = .empty;
    errdefer freeRemainingList(allocator, &functions);

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) {
            continue;
        }
        var fields = std.mem.splitScalar(u8, line, '\t');
        const file = fields.next() orelse continue;
        const function = fields.next() orelse continue;
        const occurrence = std.fmt.parseInt(usize, fields.next() orelse continue, 10) catch continue;
        const owned_file = try allocator.dupe(u8, file);
        errdefer allocator.free(owned_file);
        const owned_function = try allocator.dupe(u8, function);
        errdefer allocator.free(owned_function);
        try functions.append(allocator, .{ .file = owned_file, .function = owned_function, .occurrence = occurrence });
    }
    return functions.toOwnedSlice(allocator);
}

pub fn freeRemaining(allocator: std.mem.Allocator, functions: []Function) void {
    for (functions) |entry| {
        allocator.free(entry.file);
        allocator.free(entry.function);
    }
    allocator.free(functions);
}

fn freeRemainingList(allocator: std.mem.Allocator, functions: *std.ArrayList(Function)) void {
    for (functions.items) |entry| {
        allocator.free(entry.file);
        allocator.free(entry.function);
    }
    functions.deinit(allocator);
}

// Writes `data` to `path`, creating the directories above it. Every file this module writes goes
// through here so the directory is made in one place.
fn writeWholeFile(io: std.Io, path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        try std.Io.Dir.cwd().createDirPath(io, parent);
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("handover.test.zig");
}
