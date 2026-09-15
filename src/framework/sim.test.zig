const std = @import("std");
const sim = @import("sim.zig");

// A fake subject with one call site that can fail two ways, used to prove `exploreAll` actually
// exercises every declared failure at every recorded point rather than only the ones a scenario
// happens to hit. Nothing here is specific to a consuming project: a package's own tests, not this
// file, are what prove the framework against a real effect.
const widget_failures = [_]sim.Failure{
    .{ .name = "jammed", .err = error.Jammed },
    .{ .name = "stuck", .err = error.Stuck },
};

// Recovers from every failure `widget_failures` names, so a subject built from this proves
// `exploreAll` accepts a run that handles what it injects.
const RecoveringWidget = struct {
    opened: bool = false,

    fn run(ctx: *anyopaque, injector: *sim.Injector) anyerror!void {
        const self: *RecoveringWidget = @ptrCast(@alignCast(ctx));
        self.open(injector) catch {
            self.opened = false;
            return;
        };
    }

    fn open(self: *RecoveringWidget, injector: *sim.Injector) !void {
        if (injector.check(@src(), 0, &widget_failures)) |failure| {
            return failure.err;
        }
        self.opened = true;
    }
};

// Recovers from "jammed" but lets "stuck" propagate, used to prove `exploreAll` reports a run that
// does not handle every declared failure rather than passing regardless of what was injected.
const PartlyBrokenWidget = struct {
    fn run(ctx: *anyopaque, injector: *sim.Injector) anyerror!void {
        _ = ctx;
        if (injector.check(@src(), 0, &widget_failures)) |failure| {
            if (failure.err == error.Jammed) {
                return;
            }
            return failure.err;
        }
    }
};

test "exploreAll passes a subject that recovers from every declared failure" {
    var widget = RecoveringWidget{};
    const subject: sim.ExploreSubject = .{ .ctx = &widget, .run = RecoveringWidget.run };
    try sim.exploreAll(std.testing.allocator, .{ .subject = subject });
}

test "exploreAll fails a subject that does not recover from a declared failure" {
    var placeholder_ctx: u8 = 0;
    const subject: sim.ExploreSubject = .{ .ctx = &placeholder_ctx, .run = PartlyBrokenWidget.run };
    try std.testing.expectError(error.Stuck, sim.exploreAll(std.testing.allocator, .{ .subject = subject }));
}

// One invariant recorded a violation, for the two tests below to assert exploreAll actually ran
// (or actually skipped) it.
const InvariantSpy = struct {
    calls: usize = 0,
    violate: bool = false,

    fn check(ctx: *anyopaque) anyerror!void {
        const self: *InvariantSpy = @ptrCast(@alignCast(ctx));
        self.calls += 1;
        if (self.violate) {
            return error.InvariantViolated;
        }
    }
};

test "a cheap invariant runs after every injected run" {
    var widget = RecoveringWidget{};
    const subject: sim.ExploreSubject = .{ .ctx = &widget, .run = RecoveringWidget.run };
    var spy = InvariantSpy{};
    const invariants = [_]sim.Invariant{.{ .name = "spy", .cost = .cheap, .ctx = &spy, .check = InvariantSpy.check }};

    try sim.exploreAll(std.testing.allocator, .{ .subject = subject, .invariants = &invariants });

    // The clean pass plus one injected run per declared failure: 1 (clean) + widget_failures.len.
    try std.testing.expectEqual(1 + widget_failures.len, spy.calls);
}

test "exploreAll fails when a cheap invariant does not hold" {
    var widget = RecoveringWidget{};
    const subject: sim.ExploreSubject = .{ .ctx = &widget, .run = RecoveringWidget.run };
    var spy = InvariantSpy{ .violate = true };
    const invariants = [_]sim.Invariant{.{ .name = "spy", .cost = .cheap, .ctx = &spy, .check = InvariantSpy.check }};

    try std.testing.expectError(
        error.InvariantViolated,
        sim.exploreAll(std.testing.allocator, .{ .subject = subject, .invariants = &invariants }),
    );
}

test "Plan.parse and Plan.print round-trip a single injection" {
    var plan = try sim.Plan.parse(std.testing.allocator, "reverse_geocode.zig:214#0=connection_refused");
    defer plan.deinit(std.testing.allocator);

    var printed: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer printed.deinit();
    try plan.print(&printed.writer);
    try std.testing.expectEqualStrings("reverse_geocode.zig:214#0=connection_refused", printed.written());
}

test "Plan.parse round-trips more than one injection, comma-separated" {
    var plan = try sim.Plan.parse(
        std.testing.allocator,
        "reverse_geocode.zig:214#0=connection_refused,log.zig:12#1=timeout",
    );
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), plan.injections.len);
    try std.testing.expectEqualStrings("connection_refused", plan.injections[0].failure);
    try std.testing.expectEqualStrings("log.zig", plan.injections[1].point.file);
    try std.testing.expectEqual(@as(u32, 12), plan.injections[1].point.line);
    try std.testing.expectEqual(@as(u16, 1), plan.injections[1].point.occurrence);
}

test "Plan.parse and Plan.print round-trip a seed on its own" {
    var plan = try sim.Plan.parse(std.testing.allocator, "seed=17");
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u64, 17), plan.seed);
    try std.testing.expectEqual(@as(usize, 0), plan.injections.len);

    var printed: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer printed.deinit();
    try plan.print(&printed.writer);
    try std.testing.expectEqualStrings("seed=17", printed.written());
}

test "Plan.parse and Plan.print round-trip a seed alongside an injection" {
    var plan = try sim.Plan.parse(std.testing.allocator, "seed=17,reverse_geocode.zig:214#0=connection_refused");
    defer plan.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u64, 17), plan.seed);
    try std.testing.expectEqual(@as(usize, 1), plan.injections.len);

    var printed: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer printed.deinit();
    try plan.print(&printed.writer);
    try std.testing.expectEqualStrings("seed=17,reverse_geocode.zig:214#0=connection_refused", printed.written());
}

test "Plan.parse rejects a second seed, which would leave two worlds to replay" {
    try std.testing.expectError(error.InvalidPlan, sim.Plan.parse(std.testing.allocator, "seed=17,seed=18"));
}

test "Plan.parse rejects a seed that is not a number" {
    try std.testing.expectError(error.InvalidPlan, sim.Plan.parse(std.testing.allocator, "seed=later"));
}

test "Plan.parse rejects text with no '='" {
    try std.testing.expectError(error.InvalidPlan, sim.Plan.parse(std.testing.allocator, "reverse_geocode.zig:214#0"));
}

test "Plan.parse rejects a point with no '#'" {
    try std.testing.expectError(error.InvalidPlan, sim.Plan.parse(std.testing.allocator, "reverse_geocode.zig:214=connection_refused"));
}

test "Plan.eql compares injections, not slice identity" {
    var a = try sim.Plan.parse(std.testing.allocator, "reverse_geocode.zig:214#0=connection_refused");
    defer a.deinit(std.testing.allocator);
    var b = try sim.Plan.parse(std.testing.allocator, "reverse_geocode.zig:214#0=connection_refused");
    defer b.deinit(std.testing.allocator);
    var different = try sim.Plan.parse(std.testing.allocator, "reverse_geocode.zig:214#0=timeout");
    defer different.deinit(std.testing.allocator);

    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(different));
}

// Records the point one call site is at, then builds two separate replaying injectors from the
// same plan and checks both answer the call the same way: what proves a plan actually reproduces a
// run rather than only resembling one.
test "the same plan replayed twice returns the same failure both times" {
    const CallSite = struct {
        fn check(injector: *sim.Injector) ?sim.Failure {
            return injector.check(@src(), 0, &widget_failures);
        }
    };

    var recorder = sim.Injector.initRecording(std.testing.allocator);
    defer recorder.deinit();
    _ = CallSite.check(&recorder);
    try std.testing.expectEqual(@as(usize, 1), recorder.recorded.items.len);
    const point = recorder.recorded.items[0].point;

    const injections = [_]sim.Injection{.{ .point = point, .failure = "stuck" }};
    const plan: sim.Plan = .{ .injections = &injections };

    var first = sim.Injector.initReplaying(std.testing.allocator, plan);
    defer first.deinit();
    var second = sim.Injector.initReplaying(std.testing.allocator, plan);
    defer second.deinit();

    const first_result = CallSite.check(&first) orelse return error.TestUnexpectedResult;
    const second_result = CallSite.check(&second) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(first_result.err, second_result.err);
    try std.testing.expectEqualStrings(first_result.name, second_result.name);
}

// A point the plan does not name never fails, whatever kinds the call site declares: an injector
// only fails what its plan says to.
test "an injector replaying a plan does not fail a point the plan does not name" {
    const CallSite = struct {
        fn check(injector: *sim.Injector) ?sim.Failure {
            return injector.check(@src(), 0, &widget_failures);
        }
    };

    const injections = [_]sim.Injection{.{ .point = .{ .file = "nowhere.zig", .line = 1, .occurrence = 0 }, .failure = "jammed" }};
    const plan: sim.Plan = .{ .injections = &injections };
    var injecting = sim.Injector.initReplaying(std.testing.allocator, plan);
    defer injecting.deinit();

    try std.testing.expectEqual(@as(?sim.Failure, null), CallSite.check(&injecting));
}

test "replay runs a subject once against exactly the given plan" {
    // An empty plan fails nothing, so a clean replay succeeds exactly like an ordinary call.
    var clean_widget = RecoveringWidget{};
    const clean_subject: sim.ExploreSubject = .{ .ctx = &clean_widget, .run = RecoveringWidget.run };
    try sim.replay(std.testing.allocator, .{ .subject = clean_subject }, .{ .injections = &.{} });
    try std.testing.expect(clean_widget.opened);

    // Recording a run against this same subject gives the point its own `open` checks; replaying a
    // plan naming that point with "jammed" reproduces the failure directly, with no sweep.
    var recorder = sim.Injector.initRecording(std.testing.allocator);
    defer recorder.deinit();
    var probe = RecoveringWidget{};
    try RecoveringWidget.run(&probe, &recorder);
    const point = recorder.recorded.items[0].point;

    const injections = [_]sim.Injection{.{ .point = point, .failure = "jammed" }};
    var jammed_widget = RecoveringWidget{};
    const jammed_subject: sim.ExploreSubject = .{ .ctx = &jammed_widget, .run = RecoveringWidget.run };
    try sim.replay(std.testing.allocator, .{ .subject = jammed_subject }, .{ .injections = &injections });
    try std.testing.expect(!jammed_widget.opened);
}

test "isSynthesizedName tells a walker-invented name from one written by hand" {
    // Every kind the walker can invent, in the form it invents it: kind, line, side.
    try std.testing.expect(sim.isSynthesizedName("if:42:true"));
    try std.testing.expect(sim.isSynthesizedName("loop:7:zero"));
    try std.testing.expect(sim.isSynthesizedName("switch:1:.none"));
    try std.testing.expect(sim.isSynthesizedName("catch:99:taken"));
    try std.testing.expect(sim.isSynthesizedName("orelse:12:taken"));
    try std.testing.expect(sim.isSynthesizedName("and:3:evaluated"));
    try std.testing.expect(sim.isSynthesizedName("or:3:short-circuit"));
    try std.testing.expect(sim.isSynthesizedName("try:56:failed"));

    // Names a person writes: no line number where one is expected, or no colon at all.
    try std.testing.expect(!sim.isSynthesizedName("retryOnce:entered"));
    try std.testing.expect(!sim.isSynthesizedName("if-not-a-line:true"));
    try std.testing.expect(!sim.isSynthesizedName("loop-1-zero"));
    try std.testing.expect(!sim.isSynthesizedName("try"));
}

const fixture_source =
    \\fn covered(flag: bool) void {
    \\    if (an) annotate(log, "covered:entered", "", .{});
    \\    if (flag) {
    \\        if (an) annotate(log, "covered-true", "", .{});
    \\    } else {
    \\        if (an) annotate(log, "covered-false", "", .{});
    \\    }
    \\}
    \\
    \\fn missed() void {
    \\    if (an) annotate(log, "missed:entered", "", .{});
    \\}
;

// A file that imports the framework is simulation code: that is how `everyFunction` tells harness
// from the code it exercises, so the fixture says it the same way a real one does.
const harness_source =
    \\const sim = @import("sim");
    \\
    \\fn exercises() void {}
;

test "everyFunction lists a package's own functions and skips its simulation code" {
    const allocator = std.testing.allocator;
    const sources = [_]sim.SourceFile{
        .{ .file = "fixture.zig", .source = fixture_source },
        .{ .file = "runner.zig", .source = harness_source },
    };

    const exercised = try sim.everyFunction(allocator, &sources);
    defer sim.freeExercised(allocator, exercised);

    try std.testing.expectEqual(@as(usize, 2), exercised.len);
    try std.testing.expectEqualStrings("fixture.zig", exercised[0].file);
    try std.testing.expectEqualStrings("covered", exercised[0].function_name);
    try std.testing.expectEqualStrings("missed", exercised[1].function_name);
}

test "readCoverage reports the paths nothing annotated and fills in the tallies" {
    const allocator = std.testing.allocator;
    const sources = [_]sim.SourceFile{.{ .file = "fixture.zig", .source = fixture_source }};

    const exercised = try sim.everyFunction(allocator, &sources);
    defer sim.freeExercised(allocator, exercised);
    const tallies = try sim.initialTallies(allocator, exercised);
    defer allocator.free(tallies);

    var report: std.Io.Writer.Allocating = .init(allocator);
    defer report.deinit();

    // What a run that exercised only the true side, from `fixture.zig`'s own simulation, would have
    // annotated.
    const annotated = [_]sim.Annotated{
        .{ .module = "fixture.zig", .name = "covered:entered" },
        .{ .module = "fixture.zig", .name = "covered-true" },
    };

    var found = try sim.readCoverage(allocator, exercised, &sources, &annotated, tallies, &report);
    defer found.deinit();

    // The false side of `covered`. `missed` was never called and carries no mark of its own, so
    // nothing could have said whether its body ran: it is reported as unobservable rather than as
    // a path somebody has to go and reach.
    try std.testing.expectEqual(@as(usize, 1), found.unticked.items.len);
    try std.testing.expectEqualStrings("covered-false", found.unticked.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), found.unobservable);

    try std.testing.expectEqual(@as(usize, 2), tallies[0].paths.?.ticked);
    try std.testing.expectEqual(@as(usize, 3), tallies[0].paths.?.total);
    try std.testing.expectEqual(@as(usize, 0), tallies[1].paths.?.ticked);
}

test "failOnUntickedPaths passes an empty list and fails a list with anything in it" {
    const style = sim.Style.init(false);
    try sim.failOnUntickedPaths(&.{}, style, "report.txt");

    const unticked = [_]sim.UntickedPath{.{
        .file = "fixture.zig",
        .function = "covered",
        .line = 5,
        .name = "covered-false",
    }};
    try std.testing.expectError(error.SimCoveragePathsUnticked, sim.failOnUntickedPaths(&unticked, style, "report.txt"));
}

test "isScenario accepts a scenario's own signature and nothing else" {
    const Scenarios = struct {
        const Subject = struct { allocator: std.mem.Allocator };

        fn scenario(ctx: *anyopaque, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
            _ = ctx;
            _ = injector;
            _ = checklist;
        }

        // A scenario naming its own subject type rather than taking the erased pointer, which is
        // what a scenario written beside the module it exercises does.
        fn typedScenario(subject: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
            _ = subject;
            _ = injector;
            _ = checklist;
        }

        // A context that is not a single-item pointer is not a subject, so this is not a scenario
        // however much the rest of it matches.
        fn sliceContext(ctx: []const u8, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
            _ = ctx;
            _ = injector;
            _ = checklist;
        }

        fn helper(value: usize) usize {
            return value;
        }
    };

    try std.testing.expect(sim.isScenario(@TypeOf(Scenarios.scenario)));
    try std.testing.expect(sim.isScenario(@TypeOf(Scenarios.typedScenario)));
    try std.testing.expect(!sim.isScenario(@TypeOf(Scenarios.sliceContext)));
    try std.testing.expect(!sim.isScenario(@TypeOf(Scenarios.helper)));
    try std.testing.expect(!sim.isScenario(usize));
}

// A file name no source in this repository carries, so a declaration named against it can only be
// the one the test wrote. `accountFor` reads the name and the flag it is given rather than opening
// anything, which is what lets these run without a source file at all.
const fixture_file = "fixture.zig";

test "accountFor treats any declaration in a simulation file as accounted for" {
    try std.testing.expectEqual(
        sim.Accounting.structural,
        sim.accountFor(
            &.{},
            fixture_file,
            .{ .name = "fixtureHarnessHelper", .line = 1, .occurrence = 0 },
            true,
        ),
    );
}

test "accountFor reports a real, unregistered declaration as unaccounted rather than skipping it" {
    try std.testing.expectEqual(
        sim.Accounting.unaccounted,
        sim.accountFor(
            &.{},
            fixture_file,
            .{ .name = "fixtureRealFunction", .line = 2, .occurrence = 0 },
            false,
        ),
    );
}

test "accountFor finds a real declaration once it is registered" {
    const registered = [_]sim.FunctionTally{
        .{ .file = fixture_file, .function = "fixtureRealFunction" },
    };

    try std.testing.expectEqual(
        sim.Accounting.registered,
        sim.accountFor(
            &registered,
            fixture_file,
            .{ .name = "fixtureRealFunction", .line = 2, .occurrence = 0 },
            false,
        ),
    );
}

test "accountFor holds a declaration to account wherever it is not simulation code" {
    // The same name that is harness inside a simulation file has to be accounted for anywhere else:
    // what makes a declaration harness is the file it sits in, not the name it carries.
    try std.testing.expectEqual(
        sim.Accounting.unaccounted,
        sim.accountFor(
            &.{},
            "other.zig",
            .{ .name = "fixtureHarnessHelper", .line = 3, .occurrence = 0 },
            false,
        ),
    );
}

// A package's simulation in miniature, for the discovery tests below: one module file holding a
// scenario, a seed scenario and an exploration, and a root declaring the recorder a run records
// into, exactly as a real package does. Written here rather than exercised through a real package so a
// failure names the walk rather than whatever the package happened to declare.
//
// Each one records that it ran in something the walk itself handed it, so nothing here keeps state
// of its own between tests: the scenario counts up through the log it was given, the seed scenario
// moves the clock on the world it was given, and the exploration is proved by the injections
// `everyExploration` reports, which only happen when a clean pass recorded the point.

// The log a scenario is handed, which is the annotation channel's: there is one recorder and it
// hands back one type. The fixtures below count what ran in a variable of their own rather than in
// the log, which carries no room for it.
const annotate_mod = @import("log");
const FakeLog = annotate_mod.Log;

// How many times the fixture scenarios below were called.
var fixture_ran: usize = 0;

const FakeModuleSimulation = struct {
    pub fn runSomethingCoverageScenario(subject: *sim.Subject(FakeLog), injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
        _ = injector;
        _ = checklist;
        // What a real scenario does: it exercises code that annotates, and the run reads the name back
        // off the recorder. Counting as well, for the tests that hand in a recorder of their own.
        annotate_mod.annotate(subject.log, "scenario-ran", "", .{});
        fixture_ran += 1;
    }

    pub fn runSomethingSeedScenario(run: *sim.SeedRun) anyerror!void {
        if (run.env.seed == 0) {
            return error.TestUnexpectedResult;
        }
        run.env.advanceClock(@intCast(run.seed_count));
    }

    pub fn exploreSomething(allocator: std.mem.Allocator, injector: *sim.Injector) anyerror!void {
        _ = allocator;
        _ = injector.check(@src(), 0, &widget_failures);
    }
};

const FakeSimulationRoot = struct {
    pub const simulations = .{FakeModuleSimulation};

    // A recorder of the fixture's own, for the tests that hand one in explicitly. `standard` no
    // longer takes one: there is one recorder and it is the framework's.
    pub const Recorder = struct {
        pub fn init(self: *Recorder, allocator: std.mem.Allocator) void {
            _ = allocator;
            self.* = .{};
            fixture_ran = 0;
        }

        pub fn log(self: *Recorder) FakeLog {
            _ = self;
            return .{};
        }

        // One name per call the scenarios above made, which is what the run reads back.
        pub fn names(self: *Recorder, allocator: std.mem.Allocator) anyerror![]const []const u8 {
            _ = self;
            const copied = try allocator.alloc([]const u8, fixture_ran);
            for (copied) |*name| {
                name.* = try allocator.dupe(u8, "scenario-ran");
            }
            return copied;
        }

        pub fn deinit(self: *Recorder) void {
            _ = self;
        }
    };
};

// Whether a run's annotations carry a name. Asserted on rather than the count, because `annotate`
// records its own entry point beside whatever it was asked to record.
fn sawName(annotated: []const sim.Annotated, wanted: []const u8) bool {
    for (annotated) |entry| {
        if (std.mem.eql(u8, entry.name, wanted)) {
            return true;
        }
    }
    return false;
}

test "everyScenario reaches a scenario in a file the root only names" {
    var recorder: FakeSimulationRoot.Recorder = undefined;
    recorder.init(std.testing.allocator);
    defer recorder.deinit();

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    var subject: sim.Subject(FakeLog) = .{ .allocator = std.testing.allocator, .log = recorder.log(), .io = threaded.io() };

    var injector = sim.Injector.initRecording(std.testing.allocator);
    defer injector.deinit();
    var checklist = try sim.emptyChecklist(std.testing.allocator);
    defer checklist.deinit();

    fixture_ran = 0;
    sim.everyScenario(FakeSimulationRoot, &subject, &injector, &checklist);

    try std.testing.expectEqual(@as(usize, 1), fixture_ran);
}

// The whole trace pass, which is what a package gets instead of writing this sequence itself: build
// the recorder, hand every scenario a subject over its log, and copy the names out before it is
// released.
test "traceEveryScenario builds the recorder, walks every scenario and returns what they recorded" {
    const annotated = try sim.traceEveryScenario(FakeSimulationRoot, FakeSimulationRoot.Recorder, std.testing.allocator);
    defer sim.freeAnnotated(std.testing.allocator, annotated);

    try std.testing.expect(sawName(annotated, "scenario-ran"));
}

// What the build generates: each file tagged with the module it exercises, so what its scenarios
// annotate is attributed to that module rather than to whatever else the run happened to reach.
const FakeTaggedRoot = struct {
    pub const simulations = .{
        .{ .module = "fixture.zig", .scenarios = FakeModuleSimulation },
    };

    pub const Recorder = FakeSimulationRoot.Recorder;
};

test "traceEveryScenario tags what a file annotated with the module that file exercises" {
    const annotated = try sim.traceEveryScenario(FakeTaggedRoot, FakeTaggedRoot.Recorder, std.testing.allocator);
    defer sim.freeAnnotated(std.testing.allocator, annotated);

    try std.testing.expectEqual(@as(usize, 1), annotated.len);
    try std.testing.expectEqualStrings("fixture.zig", annotated[0].module);
}

// The rule the whole attribution exists for: a function reached on the way through another module's
// scenario is that module's coverage, so this one's paths stay unticked until its own simulation
// exercises it.
test "readCoverage ignores an annotation another module's simulation emitted" {
    const allocator = std.testing.allocator;
    const sources = [_]sim.SourceFile{.{ .file = "fixture.zig", .source = fixture_source }};

    const exercised = try sim.everyFunction(allocator, &sources);
    defer sim.freeExercised(allocator, exercised);
    const tallies = try sim.initialTallies(allocator, exercised);
    defer allocator.free(tallies);

    var report: std.Io.Writer.Allocating = .init(allocator);
    defer report.deinit();

    const annotated = [_]sim.Annotated{
        .{ .module = "caller.zig", .name = "covered:entered" },
        .{ .module = "caller.zig", .name = "covered-true" },
    };

    var found = try sim.readCoverage(allocator, exercised, &sources, &annotated, tallies, &report);
    defer found.deinit();

    try std.testing.expectEqual(@as(usize, 0), tallies[0].paths.?.ticked);
}

test "everySeedScenario reaches a seed scenario in a file the root only names" {
    var env = sim.Environment.fromSeed(7);
    var run: sim.SeedRun = .{ .allocator = std.testing.allocator, .env = &env, .seed_count = 4 };

    try sim.everySeedScenario(FakeSimulationRoot, &run);

    try std.testing.expectEqual(@as(i64, 4), env.clock_ms);
}

test "everyExploration exercises an exploration once per declared failure it recorded" {
    const injected = try sim.everyExploration(FakeSimulationRoot, std.testing.allocator);

    try std.testing.expectEqual(widget_failures.len, injected);
}

test "standard builds a simulation from what a root and its files declare" {
    const built = sim.standard(FakeSimulationRoot);

    try std.testing.expectEqual(sim.default_seeds.len, built.seeds.len);
    try std.testing.expect(built.replay != null);

    const annotated = try built.trace(std.testing.allocator);
    defer sim.freeAnnotated(std.testing.allocator, annotated);
    try std.testing.expect(sawName(annotated, "scenario-ran"));
}

// A root with no exploration has no plan to replay either, which is what `replay` being null says.
test "standard leaves replay null for a simulation with no exploration" {
    const Quiet = struct {
        pub const Recorder = struct {
            pub fn init(self: *Recorder, allocator: std.mem.Allocator) void {
                _ = self;
                _ = allocator;
            }

            pub fn log(self: *Recorder) FakeLog {
                _ = self;
                return .{};
            }

            pub fn names(self: *Recorder, allocator: std.mem.Allocator) anyerror![]const []const u8 {
                _ = self;
                _ = allocator;
                return &.{};
            }

            pub fn deinit(self: *Recorder) void {
                _ = self;
            }
        };
    };

    try std.testing.expect(sim.standard(Quiet).replay == null);
}

test "failuresFrom names one failure per field of the enum it is built from" {
    const Kind = enum { first, second, third };
    const built = sim.failuresFrom(Kind, error.Jammed);

    try std.testing.expectEqual(@as(usize, 3), built.len);
    try std.testing.expectEqualStrings("first", built[0].name);
    try std.testing.expectEqualStrings("third", built[2].name);
    try std.testing.expectEqual(error.Jammed, built[1].err);
    try std.testing.expectEqual(Kind.second, sim.nameToEnum(Kind, built[1].name));
}

test "isSeedScenario and isExploration accept their own signatures and nothing else" {
    const Shapes = struct {
        fn seedScenario(run: *sim.SeedRun) anyerror!void {
            _ = run;
        }

        fn exploration(allocator: std.mem.Allocator, injector: *sim.Injector) anyerror!void {
            _ = allocator;
            _ = injector;
        }

        fn neither(value: usize) usize {
            return value;
        }
    };

    try std.testing.expect(sim.isSeedScenario(@TypeOf(Shapes.seedScenario)));
    try std.testing.expect(!sim.isSeedScenario(@TypeOf(Shapes.exploration)));
    try std.testing.expect(sim.isExploration(@TypeOf(Shapes.exploration)));
    try std.testing.expect(!sim.isExploration(@TypeOf(Shapes.seedScenario)));
    try std.testing.expect(!sim.isExploration(@TypeOf(Shapes.neither)));
}

test "the path counts add up every function's own, and leave a function with no checklist out" {
    const tallies = [_]sim.FunctionTally{
        .{ .file = "a.zig", .function = "one", .paths = .{ .ticked = 3, .total = 4 } },
        .{ .file = "a.zig", .function = "two", .paths = .{ .ticked = 2, .total = 2, .unobservable = 5 } },
        .{ .file = "b.zig", .function = "three" },
    };

    const counts = sim.pathCounts(&tallies);
    try std.testing.expectEqual(@as(usize, 5), counts.ticked);
    // The unobservable branches are in neither count, so full coverage stays reachable.
    try std.testing.expectEqual(@as(usize, 6), counts.total);
}

test "the path counts are zero when nothing was fault tested" {
    const counts = sim.pathCounts(&.{});
    try std.testing.expectEqual(@as(usize, 0), counts.ticked);
    try std.testing.expectEqual(@as(usize, 0), counts.total);
}

test "a file with a tally is tested and one with none has nothing to test" {
    const sources = [_]sim.SourceFile{
        .{ .file = "a.zig", .source = "pub fn one() void {}\n" },
        .{ .file = "b.zig", .source = "pub const answer = 1;\n" },
    };
    const tallies = [_]sim.FunctionTally{
        .{ .file = "a.zig", .function = "one", .paths = .{ .ticked = 1, .total = 1 } },
    };

    const files = try sim.countFiles(std.testing.allocator, &sources, &tallies);
    defer std.testing.allocator.free(files.untested);

    try std.testing.expectEqual(@as(usize, 2), files.found);
    try std.testing.expectEqual(@as(usize, 1), files.tested);
    try std.testing.expectEqual(@as(usize, 1), files.untested.len);
    try std.testing.expectEqualStrings("b.zig", files.untested[0]);
}

test "harness code is not counted among the files a run found" {
    const sources = [_]sim.SourceFile{
        .{ .file = "a.zig", .source = "pub fn one() void {}\n" },
        .{ .file = "a.sim.zig", .source = "const sim = @import(\"sim\");\n" },
    };
    const tallies = [_]sim.FunctionTally{
        .{ .file = "a.zig", .function = "one", .paths = .{ .ticked = 1, .total = 1 } },
    };

    const files = try sim.countFiles(std.testing.allocator, &sources, &tallies);
    defer std.testing.allocator.free(files.untested);

    try std.testing.expectEqual(@as(usize, 1), files.found);
    try std.testing.expectEqual(@as(usize, 0), files.untested.len);
}

test "a file is harness code when it imports the framework" {
    try std.testing.expect(sim.isHarness("const sim = @import(\"sim\");\n"));
    try std.testing.expect(!sim.isHarness("const std = @import(\"std\");\n"));
}

test "a file holding the framework's own import inside a string is not harness code" {
    try std.testing.expect(!sim.isHarness("const header = \"const sim = @import(\\\"sim\\\");\";\n"));
    try std.testing.expect(!sim.isHarness(
        \\const header =
        \\    \\\\const sim = @import("sim");
        \\;
        \\
    ));
    try std.testing.expect(!sim.isHarness("// const sim = @import(\"sim\");\n"));
}

test "a name the walker made up is told apart from one somebody wrote" {
    try std.testing.expect(sim.isSynthesizedName("if:34:true"));
    try std.testing.expect(sim.isSynthesizedName("loop:52:zero"));
    try std.testing.expect(sim.isSynthesizedName("switch:41:.gigabytes"));
    try std.testing.expect(!sim.isSynthesizedName("format-file-size-entered"));
    try std.testing.expect(!sim.isSynthesizedName("if-something"));
}

test "the names a run annotated are copied out in the order they were emitted" {
    const entries = [_]struct { message: []const u8 }{
        .{ .message = "first" },
        .{ .message = "second" },
    };

    const names = try sim.annotatedNames(std.testing.allocator, &entries);
    defer sim.freeNames(std.testing.allocator, names);

    try std.testing.expectEqual(@as(usize, 2), names.len);
    try std.testing.expectEqualStrings("first", names[0]);
    try std.testing.expectEqualStrings("second", names[1]);
}

test "a tally is found by name when only one declaration carries it" {
    var tallies = [_]sim.FunctionTally{
        .{ .file = "a.zig", .function = "one" },
        .{ .file = "a.zig", .function = "two" },
    };

    try std.testing.expect(sim.tallyIfRegistered(&tallies, "one") == &tallies[0]);
    try std.testing.expect(sim.tallyIfRegistered(&tallies, "missing") == null);
    try std.testing.expect(sim.tallyFor(&tallies, "two") == &tallies[1]);
}

test "the source of a file a run read is found by its own name" {
    const sources = [_]sim.SourceFile{
        .{ .file = "a.zig", .source = "pub fn one() void {}\n" },
    };
    try std.testing.expectEqualStrings("pub fn one() void {}\n", sim.sourceFor(&sources, "a.zig"));
}

test "the report path is where the run was told to write it" {
    const args = sim.Args{};
    try std.testing.expectEqualStrings(sim.default_report_path, args.report_path);
}

test "a failure list that is empty does not end the run" {
    try sim.failOnUntickedPaths(&.{}, .init(false), "report.txt");
}

test "a failure list that is not empty ends the run" {
    const unticked = [_]sim.UntickedPath{
        .{ .file = "a.zig", .function = "one", .line = 3, .name = "if:3:false" },
    };
    try std.testing.expectError(error.SimCoveragePathsUnticked, sim.failOnUntickedPaths(&unticked, .init(false), "report.txt"));
}

test "printing the unticked paths says nothing about a run with none" {
    sim.printUntickedPaths(&.{}, .init(false), "report.txt");
}

test "an empty checklist has nothing on it" {
    var checklist = try sim.emptyChecklist(std.testing.allocator);
    defer checklist.deinit();
    try std.testing.expectEqual(@as(usize, 0), checklist.paths.len);
}

test "the tallies a run starts with are one per function, with nothing ticked" {
    const exercised = [_]sim.Exercised{
        .{ .file = "a.zig", .function_name = "one" },
        .{ .file = "a.zig", .function_name = "two", .occurrence = 1 },
    };
    const tallies = try sim.initialTallies(std.testing.allocator, &exercised);
    defer std.testing.allocator.free(tallies);

    try std.testing.expectEqual(@as(usize, 2), tallies.len);
    try std.testing.expectEqualStrings("one", tallies[0].function);
    try std.testing.expectEqual(@as(usize, 1), tallies[1].occurrence);
    try std.testing.expectEqual(@as(?@TypeOf(tallies[0].paths.?), null), tallies[0].paths);
}

test "the footer and the tallies print without a terminal" {
    // Nothing reads these back: what is asserted is that they run with colour off, which is how a
    // captured run and a smoke test read them.
    const tallies = [_]sim.FunctionTally{
        .{ .file = "a.zig", .function = "one", .paths = .{ .ticked = 1, .total = 1 } },
        .{ .file = "a.zig", .function = "two", .paths = .{ .ticked = 0, .total = 2, .unobservable = 1 } },
        .{ .file = "b.zig", .function = "three" },
    };
    const untested = [_][]const u8{"c.zig"};
    sim.printTallies(&tallies, .{ .found = 3, .tested = 2, .untested = &untested }, 4, .init(false));
    sim.printCoverageFooter(32, 7, "tmp/sim-coverage-report.txt", .init(false));
}

test "a complete test run wants every function" {
    sim.only_file = "";
    sim.only_function = "";
    defer {
        sim.only_file = "";
        sim.only_function = "";
    }

    try std.testing.expect(!sim.isIndividualTest());
    try std.testing.expect(sim.isWanted("src/a.zig", "first"));
    try std.testing.expect(sim.isWanted("src/b.zig", "second"));
}

test "an individual test over one file wants every function in it and nothing outside it" {
    sim.only_file = "src/a.zig";
    sim.only_function = "";
    defer {
        sim.only_file = "";
        sim.only_function = "";
    }

    try std.testing.expect(sim.isIndividualTest());
    try std.testing.expect(sim.isWanted("src/a.zig", "first"));
    try std.testing.expect(sim.isWanted("src/a.zig", "second"));
    try std.testing.expect(!sim.isWanted("src/b.zig", "first"));
}

test "an individual test over one name wants it wherever it is declared" {
    sim.only_file = "";
    sim.only_function = "first";
    defer {
        sim.only_file = "";
        sim.only_function = "";
    }

    try std.testing.expect(sim.isIndividualTest());
    try std.testing.expect(sim.isWanted("src/a.zig", "first"));
    try std.testing.expect(sim.isWanted("src/b.zig", "first"));
    try std.testing.expect(!sim.isWanted("src/a.zig", "second"));
}

test "the two together are an individual test over one function in one file" {
    // A name declared in more than one file is pinned to one of them by naming both.
    sim.only_file = "src/a.zig";
    sim.only_function = "first";
    defer {
        sim.only_file = "";
        sim.only_function = "";
    }

    try std.testing.expect(sim.isWanted("src/a.zig", "first"));
    try std.testing.expect(!sim.isWanted("src/b.zig", "first"));
    try std.testing.expect(!sim.isWanted("src/a.zig", "second"));
}

test "the walk that reads a package's source leaves out a directory the build excluded" {
    // The build leaves the directory out of what it compiles, and this walk is the other half: it
    // reads the tree again to build the checklist. A file skipped by one and read by the other goes
    // on the checklist with nothing compiled to exercise it, so every path of it stays unticked.
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const root = "tmp/sim-fixtures/excluded-walk";
    std.Io.Dir.cwd().deleteTree(io, root) catch {};
    defer std.Io.Dir.cwd().deleteTree(io, root) catch {};
    try std.Io.Dir.cwd().createDirPath(io, root ++ "/test");
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = root ++ "/thing.zig", .data = "" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = root ++ "/test/harness.zig", .data = "" });

    const sources = try sim.readSources(std.testing.allocator, io, root, ".", &.{"test"});
    defer {
        for (sources) |source| {
            std.testing.allocator.free(source.file);
            std.testing.allocator.free(source.source);
        }
        std.testing.allocator.free(sources);
    }

    try std.testing.expectEqual(@as(usize, 1), sources.len);
    try std.testing.expectEqualStrings("thing.zig", sources[0].file);
}
