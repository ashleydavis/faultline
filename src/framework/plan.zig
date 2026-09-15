const std = @import("std");
const point_mod = @import("point.zig");
const Point = point_mod.Point;

// One point failing one way, the smallest unit a plan carries.
pub const Injection = struct {
    point: Point,
    failure: []const u8,

    // Whether two injections name the same point and the same failure.
    pub fn eql(self: Injection, other: Injection) bool {
        return self.point.eql(other.point) and std.mem.eql(u8, self.failure, other.failure);
    }
};

// A run's whole identity: which points fail and how. `--replay` takes one of these back as text
// and reproduces the run it describes with no sweep and no search. Every run this repository's
// harness actually produces holds exactly one injection, since only one point ever fails in a
// given run; the type itself is a list because printing and parsing do not need to assume that,
// and a plan is still what a failing run's report prints regardless of how many entries it holds.
pub const Plan = struct {
    injections: []const Injection,

    // The seed the failing run was built from, where it had one: a seed scenario's world comes from
    // a seed rather than from an injected fault, so without this a failure there could not be
    // replayed at all. Written as `seed=<n>` in the text, so one `--replay` reproduces whichever
    // kind of failure was reported and there is no second flag to pick between.
    seed: ?u64 = null,

    // Whether `point` has a failure named in this plan, and if so, which. `search.zig` calls this
    // to decide what an injector handed this plan should answer at a given point.
    pub fn failureFor(self: Plan, point: Point) ?[]const u8 {
        for (self.injections) |injection| {
            if (injection.point.eql(point)) {
                return injection.failure;
            }
        }
        return null;
    }

    // Whether two plans hold the same injections, in the same order: what a replay is checked
    // against to prove it reproduced the same run rather than merely not crashing.
    pub fn eql(self: Plan, other: Plan) bool {
        if (self.seed != other.seed) {
            return false;
        }
        if (self.injections.len != other.injections.len) {
            return false;
        }
        for (self.injections, other.injections) |mine, theirs| {
            if (!mine.eql(theirs)) {
                return false;
            }
        }
        return true;
    }

    // Prints a plan the way `--replay` reads it back: an optional "seed=<n>" first, then
    // "file:line#occurrence=failure" per injection, all comma-separated.
    pub fn print(self: Plan, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.seed) |seed| {
            try writer.print("seed={d}", .{seed});
        }
        for (self.injections, 0..) |injection, index| {
            if (index > 0 or self.seed != null) {
                try writer.print(",", .{});
            }
            try writer.print("{f}={s}", .{ injection.point, injection.failure });
        }
    }

    // Parses the text `--replay` was given, the inverse of `print`: comma-separated
    // "file:line#occurrence=failure" entries. `allocator` owns the returned slice; the point and
    // failure strings inside it point into `text` itself, so `text` has to outlive the `Plan`,
    // exactly as `std.process.Init.Minimal`'s argument slices already outlive the run that reads
    // them.
    pub fn parse(allocator: std.mem.Allocator, text: []const u8) !Plan {
        var injections: std.ArrayList(Injection) = .empty;
        errdefer injections.deinit(allocator);

        var seed: ?u64 = null;
        var entries = std.mem.splitScalar(u8, text, ',');
        while (entries.next()) |entry| {
            if (std.mem.startsWith(u8, entry, seed_prefix)) {
                if (seed != null) {
                    return error.InvalidPlan;
                }
                seed = std.fmt.parseInt(u64, entry[seed_prefix.len..], 10) catch return error.InvalidPlan;
                continue;
            }
            try injections.append(allocator, try parseInjection(entry));
        }

        return .{ .injections = try injections.toOwnedSlice(allocator), .seed = seed };
    }

    // Frees what `parse` allocated. `failureFor`/`print`/`eql` read only slices into the text
    // `parse` was given, so this is the one thing `Plan` itself owns.
    pub fn deinit(self: *Plan, allocator: std.mem.Allocator) void {
        allocator.free(self.injections);
    }
};

// How a seed is written in a plan's text. One place, since `print` and `parse` are inverses of each
// other and a mismatch between them would only show up as a replay that silently ran a different
// world.
const seed_prefix = "seed=";

fn parseInjection(entry: []const u8) !Injection {
    const equals_index = std.mem.indexOfScalar(u8, entry, '=') orelse return error.InvalidPlan;
    const point_text = entry[0..equals_index];
    const failure = entry[equals_index + 1 ..];
    if (failure.len == 0) {
        return error.InvalidPlan;
    }

    const colon_index = std.mem.lastIndexOfScalar(u8, point_text, ':') orelse return error.InvalidPlan;
    const hash_index = std.mem.lastIndexOfScalar(u8, point_text, '#') orelse return error.InvalidPlan;
    if (hash_index < colon_index) {
        return error.InvalidPlan;
    }

    const file = point_text[0..colon_index];
    const line = std.fmt.parseInt(u32, point_text[colon_index + 1 .. hash_index], 10) catch return error.InvalidPlan;
    const occurrence = std.fmt.parseInt(u16, point_text[hash_index + 1 ..], 10) catch return error.InvalidPlan;

    return .{ .point = .{ .file = file, .line = line, .occurrence = occurrence }, .failure = failure };
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("plan.test.zig");
}
