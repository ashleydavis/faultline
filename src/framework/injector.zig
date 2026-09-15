const std = @import("std");
const point_mod = @import("point.zig");
const Point = point_mod.Point;
const Failure = point_mod.Failure;
const Plan = @import("plan.zig").Plan;

// One point recorded during a clean pass, with the failures the call site declared it could fail
// with. `search.zig`'s `exploreAll` turns each of these into one injected run per failure.
pub const Recorded = struct {
    point: Point,
    failures: []const Failure,
};

// Whether an `Injector` is gathering the points a subject can fail at, or answering one of them
// from a fixed plan.
pub const Mode = enum { record, replay };

// Handed down to every simulated effect, which is the only thing that ever calls `check`: no
// production function takes one, and no call site checks whether this run wants it to fail. In
// recording mode
// nothing ever fails, so a clean pass proves the subject runs before anything is injected into it;
// in replaying mode it answers from the one plan it was built with.
pub const Injector = struct {
    allocator: std.mem.Allocator,
    mode: Mode,

    // What `check` answers from in replaying mode. Left empty in recording mode, where nothing is
    // ever consulted.
    plan: Plan = .{ .injections = &.{} },

    // What `check` appends to in recording mode. Left unused in replaying mode.
    recorded: std.ArrayList(Recorded) = .empty,

    // Builds an injector that records every point it is asked about and never fails anything.
    pub fn initRecording(allocator: std.mem.Allocator) Injector {
        return .{ .allocator = allocator, .mode = .record };
    }

    // Builds an injector that fails exactly the points `plan` names, and nothing else. `plan`'s
    // own text has to outlive this injector: `plan.zig`'s `parse` never copies it.
    pub fn initReplaying(allocator: std.mem.Allocator, plan: Plan) Injector {
        return .{ .allocator = allocator, .mode = .replay, .plan = plan };
    }

    pub fn deinit(self: *Injector) void {
        self.recorded.deinit(self.allocator);
    }

    // Asks whether the point at `src` (plus `occurrence`, for a line reached more than once)
    // should fail right now, and if so, with which of `kinds`. `kinds` is the effect's own
    // declared list of ways it can go wrong there; this never chooses among them itself, only
    // answers from what recording gathered or what the plan names.
    pub fn check(self: *Injector, src: std.builtin.SourceLocation, occurrence: u16, kinds: []const Failure) ?Failure {
        const point: Point = .{ .file = src.file, .line = src.line, .occurrence = occurrence };
        switch (self.mode) {
            .record => {
                // A recording run is bounded by how many points the subject under test asks
                // about, never by anything a caller controls, so an allocation failing here means
                // the machine is out of memory rather than this run having grown unboundedly: a
                // loud crash is the right answer, the same choice `main.zig`-adjacent entry
                // points in this repository make for a `DebugAllocator`'s own `deinit` result.
                self.recorded.append(self.allocator, .{ .point = point, .failures = kinds }) catch {
                    @panic("sim: out of memory recording a point");
                };
                return null;
            },
            .replay => {
                const wanted = self.plan.failureFor(point) orelse return null;
                for (kinds) |kind| {
                    if (std.mem.eql(u8, kind.name, wanted)) {
                        return kind;
                    }
                }
                return null;
            },
        }
    }
};

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("injector.test.zig");
}
