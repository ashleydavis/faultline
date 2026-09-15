// The deterministic simulation framework: exhaustive, point-based fault injection over a subject
// that takes an injector, plus the invariants a run checks and the plan format that reproduces one
// case directly. Ports nothing: this has no TypeScript counterpart, so no port header
// and no six-part comparison.
//
// This is the one thing a package imports. Nothing here imports anything from packages/, src/ or
// apps/ (test/repository_layout.test.zig fails the build if it ever does), and nothing here names
// a concept that belongs to one package rather than to every simulated effect: an HTTP client, a
// database, an asset, a geocode result. What an effect can fail with, and what "handled correctly"
// means for it, are entirely the calling package's own.

const auto_mod = @import("auto.zig");
const isolate_mod = @import("isolate.zig");
const network_mod = @import("network.zig");
const filesystem_mod = @import("filesystem.zig");

// The run's own filesystem, held in memory. Public so a scenario can ask it for a file that opens
// and then refuses to be read, which is the one fault an in-memory read cannot produce by itself.
pub const filesystem = filesystem_mod;
const progress_mod = @import("progress.zig");
const style_mod = @import("style.zig");
const checklist_mod = @import("checklist.zig");
// What a run records annotations into. There is one, and it is the framework's: a repository
// depends on the annotation channel and never records anything itself.
pub const DefaultRecorder = @import("recording.zig").Recorder;

pub const canExerciseAutomatically = auto_mod.canExercise;

// What the generated root file names as its panic handler. Only a root can declare one, and what it
// has to do belongs to the file that forks, so the root names this and this defers to that.
pub const panicQuietlyInChild = isolate_mod.panicQuietlyInChild;

const point_mod = @import("point.zig");

const std = @import("std");
const output_mod = @import("output.zig");

// The deterministic world every simulated run is built from: one seed in, and out come the parts no
// package owns, the seeded randomness and the clock. It lives here rather than in a package because
// every package needs exactly these and none of them belongs to one: a package that has an effect of
// its own carries that effect beside this, in its own file, rather than declaring its own copy of
// the seed, the generator and the clock.
//
// Nothing here names a package's own types. The clock is a millisecond count rather than any
// particular clock type, and randomness is `std.Random`, so a package converts either into whatever
// its own code takes as a parameter without this file knowing what that is.
//
// Fields hold their state directly rather than behind a pointer this struct does not own, so a
// `Environment` can be built on the stack and passed by pointer with nothing inside it dangling.
pub const Environment = struct {
    // The seed this run was built from. Printed by whatever reports a failing run, so passing the
    // same value back reproduces the run exactly.
    seed: u64,

    // The seeded generator behind `random()`'s default answer, and behind whatever a scenario uses
    // to choose which fault to inject, when, and on what call: the whole run, faults included, is
    // one pure function of `seed`.
    prng: std.Random.Xoshiro256,

    // Set by `forceRandom` to answer `random()` with a scripted source instead of `prng`, for a
    // scenario proving code under test survives an extreme or boundary-hitting draw rather than an
    // ordinary one. `null` until a scenario asks for that, so an `Environment` nobody has called
    // `forceRandom` on behaves exactly like a plain seeded run.
    random_override: ?std.Random = null,

    // This run's clock, in milliseconds, read through whatever clock type the package using it
    // builds from it. Starts fixed and never moves on its own, so two reads with no `advanceClock`
    // between them return the same instant: that is the "time not advancing" fault, and it is the
    // default.
    clock_ms: i64 = 0,

    // Builds a fresh, deterministic world from `seed` alone, so calling this twice with the same
    // seed and exercising the result the same way produces byte-for-byte the same run.
    pub fn fromSeed(seed: u64) Environment {
        return .{ .seed = seed, .prng = std.Random.Xoshiro256.init(seed) };
    }

    // The random source this run's code under test draws from: the scripted source set by
    // `forceRandom`, if any, otherwise the seeded `prng`.
    pub fn random(self: *Environment) std.Random {
        if (self.random_override) |overridden| {
            return overridden;
        }
        return self.prng.random();
    }

    // Overrides `random()`'s answer for the rest of this run with `scripted`, for a scenario forcing
    // a specific value, both extremes, or a sequence chosen to hit a boundary.
    pub fn forceRandom(self: *Environment, scripted: std.Random) void {
        self.random_override = scripted;
    }

    // Advances this run's clock by `ms`. A positive value is a forward jump, a negative value is a
    // backward jump, and no call at all between two reads is the "time not advancing" fault.
    pub fn advanceClock(self: *Environment, ms: i64) void {
        self.clock_ms += ms;
    }
};

pub const Point = point_mod.Point;
pub const Failure = point_mod.Failure;

const plan_mod = @import("plan.zig");
pub const Injection = plan_mod.Injection;
pub const Plan = plan_mod.Plan;

const injector_mod = @import("injector.zig");
pub const Injector = injector_mod.Injector;
pub const Recorded = injector_mod.Recorded;

const invariant_mod = @import("invariant.zig");
pub const Cost = invariant_mod.Cost;
pub const Invariant = invariant_mod.Invariant;

const search_mod = @import("search.zig");
pub const ExploreSubject = search_mod.Subject;
pub const ExploreOptions = search_mod.ExploreOptions;
pub const ExploreCounts = search_mod.Counts;
pub const exploreAll = search_mod.exploreAll;
pub const replay = search_mod.replay;

const report_mod = @import("report.zig");
pub const printFailure = report_mod.printFailure;

const coverage_mod = @import("coverage.zig");
pub const CoveragePath = coverage_mod.Path;
pub const Checklist = coverage_mod.Checklist;
pub const buildChecklist = coverage_mod.build;
pub const Call = coverage_mod.Call;
pub const listCalls = coverage_mod.listCalls;
pub const freeCalls = coverage_mod.freeCalls;
pub const buildChecklistOccurrence = coverage_mod.buildOccurrence;
pub const Declaration = coverage_mod.Declaration;
pub const listDeclarations = coverage_mod.listDeclarations;
pub const functionAtLine = coverage_mod.functionAtLine;
pub const freeDeclarations = coverage_mod.freeDeclarations;

const coverage_search_mod = @import("coverage_search.zig");
const covered_lines = @import("covered_lines.zig");
const handover = @import("handover.zig");
const rounds = @import("rounds.zig");
pub const CoverageSubject = coverage_search_mod.CoverageSubject;
pub const ExploreCoverageOptions = coverage_search_mod.ExploreCoverageOptions;
pub const exploreCoverage = coverage_search_mod.exploreCoverage;
pub const CoverageCounts = coverage_search_mod.Counts;

// What kcov saw run, read back off the file it writes, and the set a checklist is ticked from.
pub const CoveredLines = covered_lines.CoveredLines;
pub const LineSet = covered_lines.LineSet;
pub const readCobertura = covered_lines.readCobertura;
pub const parseCobertura = covered_lines.parseCobertura;

// The whole simulation run, which is one run for the whole repository: read the arguments, list
// the functions every package's sources declare, build a checklist for each, exercise every package's
// scenarios, tick what they annotated, report what nothing reached, and end the process red when
// something did not. None of it knows a package: a package declares its scenarios, its seeds and
// its effects, and the build says where its files are.

// The arguments a simulation binary reads off its own argument vector, past `argv[0]`. There is no
// argument that widens or narrows what a run does: `--replay` runs a strict subset of the ordinary
// run and exists only to reproduce a failure it has already reported. One flag rather than two,
// because a failure is reproduced from what the report printed without the reader having to work
// out which kind of failure it was: the plan carries the seed when the failing run had one.
pub const Args = struct {
    replay_plan: ?[]const u8 = null,

    // Where the full checklist is written. An option rather than a constant because the tool is run
    // against whatever repository it is pointed at, and the checklist belongs with the rest of what
    // that run generated rather than inside the repository being fault tested.
    report_path: []const u8 = default_report_path,

    // Runs an individual test over one file, named the way the report names it. Empty is a complete
    // test run.
    only_file: []const u8 = "",

    // Runs an individual test over functions of one name. Empty is a complete test run. Combines
    // with `only_file`, so a name declared in more than one file is pinned to one by naming both.
    only_function: []const u8 = "",

    // Where the code being fault tested is, for reading its source back. Only reading: a run starts in
    // a scratch directory of its own, never in the repository, because the functions it exercises are
    // the repository's own and some of them create files and directories. Exercising those with the
    // repository as the working directory is what once filled somebody's checkout with hundreds of
    // thousands of generated files, every one of them made by their own code doing exactly what it
    // was written to do, in the wrong place.
    repository: []const u8 = ".",

    // Colour off, whatever the terminal is. `NO_COLOR` in the environment does the same, and both
    // exist because this output is read by a person at a terminal and by whatever captures a log.
    no_color: bool = false,

    // Runs one round of exercising on behalf of the run that spawned it under kcov, and writes what
    // it reached to `handover_path` instead of printing a report.
    worker: bool = false,

    // Which round a worker is running. The runner draws different arguments each round, and only
    // the first round runs the scenarios and the seed sweep.
    round: usize = 1,

    // A file naming the functions a worker is to exercise, one `file`, `function` and `occurrence`
    // per line. Empty means every function.
    remaining_path: []const u8 = "",

    // Where a worker writes what it reached and what it cost, for the run that spawned it to read.
    handover_path: []const u8 = "",

    // The kcov binary the run reads line coverage through: a name looked up on the PATH, or a path.
    kcov: []const u8 = "kcov",

    // Where every round's kcov output goes, one directory per round under it. Relative to where the
    // run stands, which the build puts in its own cache.
    kcov_out: []const u8 = "flt-kcov",

    // The directory holding the copies of the repository's sources the run was compiled from, which
    // is what kcov is told to report on. Empty means the run cannot use kcov.
    sources_root: []const u8 = "",
};

pub fn parseArgs(args: std.process.Args) !Args {
    var iterator = args.iterate();
    defer iterator.deinit();
    _ = iterator.next(); // argv[0], the program's own path, never a flag.

    var parsed = Args{};
    while (iterator.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-color") or std.mem.eql(u8, arg, "--no-colour")) {
            parsed.no_color = true;
        } else if (std.mem.eql(u8, arg, "--report")) {
            parsed.report_path = iterator.next() orelse {
                output_mod.print("The --report argument needs a path.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--replay")) {
            parsed.replay_plan = iterator.next() orelse {
                output_mod.print("The --replay argument needs a plan.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--file")) {
            parsed.only_file = iterator.next() orelse {
                output_mod.print("The --file argument needs a path.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--function")) {
            parsed.only_function = iterator.next() orelse {
                output_mod.print("The --function argument needs a name.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--repository")) {
            parsed.repository = iterator.next() orelse {
                output_mod.print("The --repository argument needs a path.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--worker")) {
            parsed.worker = true;
        } else if (std.mem.eql(u8, arg, "--round")) {
            const text = iterator.next() orelse {
                output_mod.print("The --round argument needs a number.\n", .{});
                return error.InvalidArgument;
            };
            parsed.round = std.fmt.parseInt(usize, text, 10) catch {
                output_mod.print("The --round argument needs a number.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--remaining")) {
            parsed.remaining_path = iterator.next() orelse {
                output_mod.print("The --remaining argument needs a path.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--handover")) {
            parsed.handover_path = iterator.next() orelse {
                output_mod.print("The --handover argument needs a path.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--kcov")) {
            parsed.kcov = iterator.next() orelse {
                output_mod.print("The --kcov argument needs a path.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--kcov-out")) {
            parsed.kcov_out = iterator.next() orelse {
                output_mod.print("The --kcov-out argument needs a path.\n", .{});
                return error.InvalidArgument;
            };
        } else if (std.mem.eql(u8, arg, "--sources-root")) {
            parsed.sources_root = iterator.next() orelse {
                output_mod.print("The --sources-root argument needs a path.\n", .{});
                return error.InvalidArgument;
            };
        } else {
            output_mod.print("\"{s}\" is not an argument this run takes.\n", .{arg});
            return error.InvalidArgument;
        }
    }
    return parsed;
}

// One function a run exercises, named the way `buildChecklistOccurrence` needs to find it again.
pub const Exercised = struct {
    file: []const u8,
    function_name: []const u8,
    occurrence: usize = 0,

    // Whether anything outside its own file can call it.
    is_public: bool = false,
};

// Every function a package declares, each of which gets its own checklist. Nothing pairs a scenario
// with a function: the functions come from the walk, and what ticks their paths is what the code
// emitted while it ran. A file that imports this framework is simulation code, exercising the rest
// rather than being it, which is read from the file itself: nothing lists which files are harness,
// so nothing goes stale when one is added or renamed.
// Says which individual test this is, because a coverage number over one function looks exactly
// like the number from a complete test run, and somebody reading the second as the first would be
// wrong about how much of their code has been run.
fn printIndividualTest(style: Style) void {
    if (only_file.len != 0 and only_function.len != 0) {
        output_mod.print("{s}Individual test: {s} in {s}. Nothing else is exercised and nothing else is counted.{s}\n", .{ style.bold(), only_function, only_file, style.reset() });
        return;
    }
    if (only_file.len != 0) {
        output_mod.print("{s}Individual test: {s}. Nothing else is exercised and nothing else is counted.{s}\n", .{ style.bold(), only_file, style.reset() });
        return;
    }
    output_mod.print("{s}Individual test: every function named {s}. Nothing else is exercised and nothing else is counted.{s}\n", .{ style.bold(), only_function, style.reset() });
}

// Which individual test this run is, when it is one rather than a complete test run.
//
// Globals rather than parameters, which is the exception here and not the rule. The code that
// decides whether to call a function is generated at compile time, one layer per module and one per
// function, and every one of those layers would otherwise have to carry a filter it does nothing
// with. `isolate_mod.progress_is_watched` is a global for the same reason. They are written once,
// before any function is exercised, and the children are forked rather than started fresh, so each one
// inherits what the parent decided.
pub var only_file: []const u8 = "";
pub var only_function: []const u8 = "";

// The functions a worker round is to exercise, or null for every function. Set from the file the
// run that spawned the worker wrote, before anything is exercised, for the same reason as the two
// above.
pub var remaining: ?[]const Exercised = null;

// Which round this process is running. One for an ordinary run. The runner seeds its draws from it,
// so a later round calls every remaining function with arguments the earlier rounds did not.
pub var round: usize = 1;

// Whether a function is one this run was asked for. Every function, on a complete test run.
pub fn isWanted(file: []const u8, function_name: []const u8) bool {
    if (only_file.len != 0 and !std.mem.eql(u8, only_file, file)) {
        return false;
    }
    if (only_function.len != 0 and !std.mem.eql(u8, only_function, function_name)) {
        return false;
    }
    if (remaining) |listed| {
        var found = false;
        for (listed) |one| {
            if (std.mem.eql(u8, one.file, file) and std.mem.eql(u8, one.function_name, function_name)) {
                found = true;
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

// The functions the repository's own files declare, which is what `everyFunction` read out of the
// source. Set before anything is exercised and read by the runner.
var declared_in_source: []const Exercised = &.{};

// Whether a file declares this function itself.
//
// The runner walks the compiled module, which holds every declaration the file made and every one it
// re-exported: a file that says `pub const Value = std.json.Value;` hands the runner the standard
// library's own container methods, and a file that re-exports another module hands it that module's
// functions a second time. None of that is the file's own code, none of it appears on any checklist,
// and exercising it cost more than exercising everything that does: `ensureTotalCapacity` handed a
// capacity from a corpus spends tens of milliseconds a call reserving memory nobody asked for.
pub fn isDeclaredIn(file: []const u8, function_name: []const u8) bool {
    if (declared_in_source.len == 0) {
        return true;
    }
    for (declared_in_source) |one| {
        if (std.mem.eql(u8, one.file, file) and std.mem.eql(u8, one.function_name, function_name)) {
            return true;
        }
    }
    return false;
}

// Whether this is an individual test rather than a complete test run.
pub fn isIndividualTest() bool {
    return only_file.len != 0 or only_function.len != 0;
}

pub fn everyFunction(allocator: std.mem.Allocator, sources: []const SourceFile) ![]Exercised {
    var list: std.ArrayList(Exercised) = .empty;
    errdefer freeExercisedList(allocator, &list);

    for (sources) |source| {
        if (isHarness(source.source)) {
            continue;
        }

        const declarations = try coverage_mod.listDeclarations(allocator, source.source);
        defer coverage_mod.freeDeclarations(allocator, declarations);

        for (declarations) |declaration| {
            // An individual test reports only what it exercised. Leaving the rest in would report every
            // other function as having reached none of its paths, which is true and useless: they
            // were never called.
            if (!isWanted(source.file, declaration.name)) {
                continue;
            }
            try list.append(allocator, .{
                .file = source.file,
                .function_name = try allocator.dupe(u8, declaration.name),
                .occurrence = declaration.occurrence,
                .is_public = declaration.is_public,
            });
        }
    }

    return list.toOwnedSlice(allocator);
}

// Whether a source is simulation code: it imports this framework, which nothing being fault tested
// ever does.
//
// Tokenized rather than searched for as text, because the text appears inside string literals in
// code that is not simulation code at all: the tool's own `discover.zig` holds the generated root
// as a literal, and that literal opens by importing this framework. Searching the bytes read that
// file as a harness and dropped every function in it.
pub fn isHarness(source: [:0]const u8) bool {
    var tokenizer = std.zig.Tokenizer.init(source);
    var builtin_seen = false;
    var open_seen = false;
    while (true) {
        const token = tokenizer.next();
        switch (token.tag) {
            .eof => return false,
            .builtin => {
                builtin_seen = std.mem.eql(u8, source[token.loc.start..token.loc.end], "@import");
                open_seen = false;
            },
            .l_paren => {
                open_seen = builtin_seen;
            },
            .string_literal => {
                if (builtin_seen and open_seen and std.mem.eql(u8, source[token.loc.start..token.loc.end], framework_module)) {
                    return true;
                }
                builtin_seen = false;
                open_seen = false;
            },
            else => {
                builtin_seen = false;
                open_seen = false;
            },
        }
    }
}

// How a file says it is simulation code: the name this framework is imported under, quoted as the
// tokenizer hands a string literal back. Written once, here, since this is the module imported.
const framework_module = "\"sim\"";

fn freeExercisedList(allocator: std.mem.Allocator, list: *std.ArrayList(Exercised)) void {
    for (list.items) |entry| {
        allocator.free(entry.function_name);
    }
    list.deinit(allocator);
}

pub fn freeExercised(allocator: std.mem.Allocator, list: []const Exercised) void {
    for (list) |entry| {
        allocator.free(entry.function_name);
    }
    allocator.free(list);
}

// One tally per exercised function, built from the list itself rather than declared a second time.
pub fn initialTallies(allocator: std.mem.Allocator, list: []const Exercised) ![]FunctionTally {
    const built = try allocator.alloc(FunctionTally, list.len);
    for (list, 0..) |spec, index| {
        built[index] = .{ .file = spec.file, .function = spec.function_name, .occurrence = spec.occurrence };
    }
    return built;
}

// The name a namespace declares a function under, read from the namespace itself rather than
// written as a string: a name spelled out by hand is wrong the moment the function is renamed, and
// nothing fails when it is. Fails the build when the function is not one of the namespace's own.
pub inline fn nameOf(comptime Namespace: type, comptime function: anytype) []const u8 {
    comptime {
        var found: ?[]const u8 = null;
        for (@typeInfo(Namespace).@"struct".decls) |decl| {
            const declared = @field(Namespace, decl.name);
            if (@TypeOf(declared) != @TypeOf(function)) {
                continue;
            }
            if (&declared == &function) {
                found = decl.name;
            }
        }
        return found orelse @compileError("sim: that function is not declared in " ++ @typeName(Namespace));
    }
}

// The tally for a function named by the function itself, so nothing writes its name down.
pub fn tallyOf(tallies: []FunctionTally, comptime Namespace: type, comptime function: anytype) ?*FunctionTally {
    return tallyIfRegistered(tallies, nameOf(Namespace, function));
}

// The tally for one function when this run exercises it at all, for a fault source that adds its own
// count to whatever the coverage run already found. By function name alone: a package names the
// function it means, never the file or the directory it sits in, since where a package's own files
// live is the run's knowledge and not something a package should be able to get wrong.
//
// A name two of the package's files both declare is refused rather than guessed at, since either
// answer would be wrong half the time.
pub fn tallyIfRegistered(tallies: []FunctionTally, function_name: []const u8) ?*FunctionTally {
    var found: ?*FunctionTally = null;
    for (tallies) |*tally| {
        if (!std.mem.eql(u8, tally.function, function_name)) {
            continue;
        }
        if (found != null) {
            std.debug.panic("\"{s}\" is declared more than once in this package, so a tally cannot be found by name alone.", .{function_name});
        }
        found = tally;
    }
    return found;
}

// The same, for a caller that knows the function is registered: a name that is not is a mistake in
// the caller rather than something to carry on past.
pub fn tallyFor(tallies: []FunctionTally, function_name: []const u8) *FunctionTally {
    return tallyIfRegistered(tallies, function_name) orelse
        std.debug.panic("No tally is registered for \"{s}\".", .{function_name});
}

// A scenario is known by its type rather than by its name or by appearing on a list: a function
// taking a context, an injector and a checklist is one, and nothing else is.
//
// The context is a single-item pointer of any kind, not `*anyopaque` alone, so a scenario names the
// subject type it actually wants and reads it without a cast. `everyScenario` erases the pointer for
// a scenario that still asks for `*anyopaque`, which is what a scenario reached through some other
// context takes.
pub fn isScenario(comptime Function: type) bool {
    const info = @typeInfo(Function);
    if (info != .@"fn") {
        return false;
    }
    const params = info.@"fn".params;
    if (params.len != 3) {
        return false;
    }
    const context = params[0].type orelse return false;
    if (@typeInfo(context) != .pointer or @typeInfo(context).pointer.size != .one) {
        return false;
    }
    return params[1].type == *Injector and
        params[2].type == *Checklist;
}

// One annotation a run recorded, and the module whose own simulation emitted it. The pairing is
// what makes a function's coverage mean "this function was exercised" rather than "something,
// somewhere, happened to call it": a module reached incidentally through another module's scenario
// annotates under that other module, so its own paths stay unticked until it is exercised directly.
pub const Annotated = struct {
    // Whether this came from exercising a module's functions from their types rather than from a
    // scenario. A private function has no caller a run can reach, so what the runner reaches
    // through its file's own public functions is the only coverage it will ever have.
    from_runner: bool = false,

    // The module file this was emitted under, as the build recorded it, for example
    // `packages/text/src/sleep.zig`. Empty for a simulation the build did not tag, which matches
    // no module and therefore ticks nothing.
    module: []const u8,

    // The annotation's own name, which is what a checklist path is ticked by.
    name: []const u8,
};

// Releases what a `Simulation.trace` handed back.
pub fn freeAnnotated(allocator: std.mem.Allocator, list: []const Annotated) void {
    for (list) |entry| allocator.free(entry.name);
    allocator.free(list);
}

// The namespace one entry in a `simulations` tuple stands for. The build tags each entry with the
// module its file exercises, so an entry arrives as `.{ .module, .scenarios }`; a namespace written by
// hand is the type itself, and carries no module of its own.
fn namespaceOf(comptime entry: anytype) type {
    if (@TypeOf(entry) == type) {
        return entry;
    }
    return entry.scenarios;
}

// Which module an entry's scenarios annotate under: its own where the build tagged it, and
// otherwise whatever the namespace holding it was already under, so a namespace nested by hand
// inside a tagged one stays attributed to the same module.
fn moduleOf(comptime entry: anytype, comptime inherited: []const u8) []const u8 {
    if (@TypeOf(entry) == type) {
        return inherited;
    }
    return entry.module;
}

// The "s" that makes a count read as a sentence rather than as a form to be filled in. Written once
// here because every line that carries a count needs it.
pub fn plural(count: usize) []const u8 {
    return if (count == 1) "" else "s";
}

// One path a run left unticked, kept rather than counted so the failure can name each one.
pub const UntickedPath = struct {
    file: []const u8,
    function: []const u8,
    line: u32,
    name: []const u8,

    // The line that would have proved it, or null where no line can: what decides whether the
    // checklist asks for a scenario or for the body to be given a line of its own.
    witness: ?u32 = null,

    // Whether the build carried no code for `witness`, so no run could ever hit it.
    line_missing: bool = false,

    // Whether an annotation can be written in the branch.
    marker_room: bool = true,

    // Whether the path is the false side of an `if` with no `else`, which is proved by counting
    // the true side's annotation against the function's entries.
    counted_side: bool = false,
};

// Whether a name is one the walker synthesized for a branch that carried no annotation of its own:
// a kind, then the line, then the side. An annotation written by hand never looks like that, so the
// two failures can be told apart without opening the source. The kinds are read from
// `coverage_mod.synthesized_kinds` rather than repeated here, so a kind added there is recognised here
// without anything else being edited.
pub fn isSynthesizedName(name: []const u8) bool {
    for (coverage_mod.synthesized_kinds) |kind| {
        if (!std.mem.startsWith(u8, name, kind)) {
            continue;
        }
        const rest = name[kind.len..];
        const digits_end = std.mem.indexOfScalar(u8, rest, ':') orelse continue;
        if (digits_end == 0) {
            continue;
        }
        for (rest[0..digits_end]) |character| {
            if (!std.ascii.isDigit(character)) {
                return false;
            }
        }
        return true;
    }
    return false;
}

// Ends the run red, naming the paths nothing reached, since a run that says only how many there
// were leaves the reader to find them in a file they have to know about first. Each line carries
// the file and line a terminal can open directly, and why that path failed: a branch with no
// annotation and a branch nothing exercises are different work, and the name is what tells them apart.
// Past the first few the terminal gets a count and the report's own path instead.
pub fn failOnUntickedPaths(unticked: []const UntickedPath, style: Style, report_path: []const u8) !void {
    printUntickedPaths(unticked, style, report_path);
    if (unticked.len != 0) {
        return error.SimCoveragePathsUnticked;
    }
}

// The same list, printed without ending the run, so the checklist and the coverage number can be
// printed under it before the run returns its error.
// `report_path` is named on the line that says how many were not printed, so a reader who wants the
// rest never has to be told separately where they are.
pub fn printUntickedPaths(unticked: []const UntickedPath, style: Style, report_path: []const u8) void {
    if (unticked.len == 0) {
        return;
    }
    output_mod.print("\n  {s} {d} code path{s} that nothing reached:\n", .{ style.fail(), unticked.len, plural(unticked.len) });
    // The same limit the checklist uses, for the same reason: a first run against a repository with
    // no annotations has thousands of these, and all of them on a terminal is not a report.
    for (unticked[0..@min(unticked.len, checklist_mod.terminal_limit)]) |path| {
        if (isSynthesizedName(path.name)) {
            output_mod.print("      {s}:{d} \"{s}\" in {s}: {s}\n", .{ path.file, path.line, path.name, path.function, reasonUnticked(path) });
            continue;
        }
        // Naming the file that has to reach it is the whole of the fix, and a reader who does not
        // already know the convention would otherwise have to be told it somewhere else.
        const stem = if (std.mem.endsWith(u8, path.file, ".zig"))
            path.file[0 .. path.file.len - ".zig".len]
        else
            path.file;
        output_mod.print(
            "      {s}:{d} \"{s}\" in {s}: annotated, but {s}.sim.zig never exercised it.\n",
            .{ path.file, path.line, path.name, path.function, stem },
        );
    }

    if (unticked.len > checklist_mod.terminal_limit) {
        output_mod.print("      {s}and {d} more, all of them in {s}.{s}\n", .{
            style.dim(),
            unticked.len - checklist_mod.terminal_limit,
            report_path,
            style.reset(),
        });
    }
}

// Why a path with a synthesized name stayed unticked, in the words the report prints after it. A
// path with a line of its own that the build has code for was reachable and not reached, which is
// a scenario's job; the other three say what stops a line or an annotation proving it.
pub fn reasonUnticked(path: UntickedPath) []const u8 {
    if (path.line_missing) {
        return "the build carried no code for its line.";
    }
    if (path.witness != null) {
        return "it has a line of its own, and no call reached it.";
    }
    if (path.counted_side or !path.marker_room and std.mem.endsWith(u8, path.name, ":false")) {
        return "no line of its own, and the true side carries no annotation to count against.";
    }
    return "no line of its own, and no annotation.";
}

// What one coverage pass found: the paths nothing reached, which fail the run, and how many
// branches no annotation could ever reach, which are reported rather than counted.
pub const Coverage = struct {
    allocator: std.mem.Allocator,
    unticked: std.ArrayList(UntickedPath) = .empty,
    unobservable: usize = 0,

    pub fn deinit(self: *Coverage) void {
        for (self.unticked.items) |path| self.allocator.free(path.name);
        self.unticked.deinit(self.allocator);
    }
};

// Builds every exercised function's checklist from its current source, ticks it from what the run
// annotated under that function's own module, writes each one to `report`, and fills `tallies` with
// what it found.
// Which annotations belong to which module, and which of them the runner reached, as positions in
// the list the run recorded. Positions rather than names, so the order the run emitted them in
// survives: a loop's zero, one and many paths are decided by counting iterations between one
// traversal and the next, and a list out of order counts nothing.
const ByModule = struct {
    // One entry per module the run annotated under, each holding that module's own positions.
    modules: std.StringArrayHashMapUnmanaged(std.ArrayList(usize)) = .empty,

    // The positions the runner reached, whichever module they were recorded under.
    from_runner: std.ArrayList(usize) = .empty,

    fn deinit(self: *ByModule, allocator: std.mem.Allocator) void {
        for (self.modules.values()) |*positions| {
            positions.deinit(allocator);
        }
        self.modules.deinit(allocator);
        self.from_runner.deinit(allocator);
    }

    // The names one function's checklist is ticked from, in the order the run emitted them.
    fn namesFor(
        self: *ByModule,
        allocator: std.mem.Allocator,
        annotated: []const Annotated,
        file: []const u8,
        is_public: bool,
        names: *std.ArrayList([]const u8),
    ) !void {
        const own: []const usize = if (self.modules.getPtr(file)) |positions| positions.items else &.{};
        if (is_public) {
            for (own) |at| {
                try names.append(allocator, annotated[at].name);
            }
            return;
        }

        // Two lists, both in the run's own order, merged back into one of the same.
        var mine: usize = 0;
        var exercised_at: usize = 0;
        while (mine < own.len or exercised_at < self.from_runner.items.len) {
            const take_mine = exercised_at == self.from_runner.items.len or
                (mine < own.len and own[mine] <= self.from_runner.items[exercised_at]);
            if (take_mine) {
                try names.append(allocator, annotated[own[mine]].name);
                mine += 1;
                continue;
            }
            const at = self.from_runner.items[exercised_at];
            exercised_at += 1;
            // A position that is this module's as well has already been taken above.
            if (std.mem.eql(u8, annotated[at].module, file)) {
                continue;
            }
            try names.append(allocator, annotated[at].name);
        }
    }
};

fn groupByModule(allocator: std.mem.Allocator, annotated: []const Annotated) !ByModule {
    var grouped: ByModule = .{};
    errdefer grouped.deinit(allocator);

    for (annotated, 0..) |entry, at| {
        const found = try grouped.modules.getOrPut(allocator, entry.module);
        if (!found.found_existing) {
            found.value_ptr.* = .empty;
        }
        try found.value_ptr.append(allocator, at);
        if (entry.from_runner) {
            try grouped.from_runner.append(allocator, at);
        }
    }
    return grouped;
}

// One checklist per exercised function, built from its current source and ticked by nothing yet.
// The caller owns them, and `freeChecklists` releases them.
pub fn buildChecklists(allocator: std.mem.Allocator, exercised: []const Exercised, sources: []const SourceFile) ![]Checklist {
    var built: std.ArrayList(Checklist) = .empty;
    errdefer freeChecklistList(allocator, &built);
    for (exercised) |spec| {
        try built.append(allocator, try buildChecklistOccurrence(
            allocator,
            spec.file,
            sourceFor(sources, spec.file),
            spec.function_name,
            spec.occurrence,
        ));
    }
    return built.toOwnedSlice(allocator);
}

pub fn freeChecklists(allocator: std.mem.Allocator, checklists: []Checklist) void {
    for (checklists) |*checklist| {
        checklist.deinit();
    }
    allocator.free(checklists);
}

fn freeChecklistList(allocator: std.mem.Allocator, checklists: *std.ArrayList(Checklist)) void {
    for (checklists.items) |*checklist| {
        checklist.deinit();
    }
    checklists.deinit(allocator);
}

// Ticks every checklist from what the run annotated. Only what a module's own simulation file
// annotated ticks that module's public functions: a path reached on the way through, from a
// scenario exercising some other module, is that other module's coverage and not this one's. A
// private function has no caller a run can reach directly, so what the runner reached through some
// other file's public function counts for it too.
//
// The names are handed over in the order the run emitted them, because the false side of an `if`
// with no `else` is decided by counting one traversal at a time. Calling this again with a longer
// list, as each round does, changes nothing already ticked.
pub fn tickChecklistsFromTrace(
    allocator: std.mem.Allocator,
    checklists: []Checklist,
    exercised: []const Exercised,
    annotated: []const Annotated,
) !void {
    // What each module annotated, and what the runner reached, worked out once rather than once per
    // function. Read per function, this walked every annotation the run recorded for each of them:
    // at a quarter of a million functions' worth of names that was the larger part of the run.
    var by_module = try groupByModule(allocator, annotated);
    defer by_module.deinit(allocator);

    // The trace the file being read reached, kept while its functions are read off it.
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(allocator);
    var ticked_file: []const u8 = "";

    for (exercised, 0..) |spec, index| {
        if (!std.mem.eql(u8, ticked_file, spec.file)) {
            ticked_file = spec.file;
            names.clearRetainingCapacity();
            try by_module.namesFor(allocator, annotated, spec.file, true, &names);
        }

        if (spec.is_public) {
            checklists[index].tickFromTrace(names.items);
        } else {
            var reached: std.ArrayList([]const u8) = .empty;
            defer reached.deinit(allocator);
            try by_module.namesFor(allocator, annotated, spec.file, false, &reached);
            checklists[index].tickFromTrace(reached.items);
        }
    }
}

// Ticks every checklist from the lines kcov saw run, and marks the witness lines the build carried
// no code for. Returns how many paths this ticked that were not ticked before.
pub fn tickChecklistsFromLines(
    checklists: []Checklist,
    exercised: []const Exercised,
    covered: *const CoveredLines,
    sources_root: []const u8,
) usize {
    var newly: usize = 0;
    for (exercised, 0..) |spec, index| {
        const lines = covered.linesFor(sources_root, spec.file) orelse continue;
        const before = checklists[index].tickedCount();
        checklists[index].tickFromLines(lines);
        checklists[index].markMissingLines(lines);
        newly += checklists[index].tickedCount() - before;
    }
    return newly;
}

// Reads the ticked checklists back into what the report prints: the tallies, the paths nothing
// reached, the branches no run can observe, and the whole list written to `report`.
pub fn summariseCoverage(
    allocator: std.mem.Allocator,
    checklists: []Checklist,
    exercised: []const Exercised,
    tallies: []FunctionTally,
    report: *std.Io.Writer.Allocating,
) !Coverage {
    var found: Coverage = .{ .allocator = allocator };
    errdefer found.deinit();

    for (exercised, 0..) |spec, index| {
        const checklist = &checklists[index];

        var observable_total: usize = 0;
        var unobservable_here: usize = 0;
        for (checklist.paths) |path| {
            if (path.observable) {
                observable_total += 1;
            } else {
                unobservable_here += 1;
            }
        }
        tallies[index].paths = .{
            .ticked = checklist.tickedCount(),
            .total = observable_total,
            .unobservable = unobservable_here,
        };

        for (checklist.paths, 0..) |path, path_index| {
            if (checklist.ticked[path_index]) continue;
            // A short-circuit or a `try` has no statement position for an annotation and no line of
            // its own, so no run can tick it. Counted and listed rather than failing a run that could
            // never pass.
            if (!path.observable) {
                found.unobservable += 1;
                continue;
            }
            // `spec` outlives this loop; the checklist's own name is copied because the report keeps
            // it after the checklists are gone.
            try found.unticked.append(allocator, .{
                .file = spec.file,
                .function = spec.function_name,
                .line = path.line,
                .name = try allocator.dupe(u8, path.name),
                .witness = path.witness,
                .line_missing = path.line_missing,
                .marker_room = path.marker_room,
                .counted_side = path.not_taken != null,
            });
        }
        checklist.report(&report.writer) catch {};
    }

    return found;
}

// Builds every exercised function's checklist, ticks it from what the run annotated, writes each one
// to `report`, and fills `tallies`: the three steps above in one call, for a caller with no rounds
// to spread them over.
pub fn readCoverage(
    allocator: std.mem.Allocator,
    exercised: []const Exercised,
    sources: []const SourceFile,
    annotated: []const Annotated,
    tallies: []FunctionTally,
    report: *std.Io.Writer.Allocating,
) !Coverage {
    const checklists = try buildChecklists(allocator, exercised, sources);
    defer freeChecklists(allocator, checklists);
    try tickChecklistsFromTrace(allocator, checklists, exercised, annotated);
    return summariseCoverage(allocator, checklists, exercised, tallies, report);
}

// Every function a run exercised, and how it went, one line each under the file it lives in.
// How long this function's own calls took, on the end of its line, so a reader looking for where a
// run spends its minutes reads down one column rather than timing anything themselves. Left off
// where it rounds to nothing, since a column of zeroes is noise: what is worth seeing is the
// handful of functions that cost seconds.
fn printFunctionTime(tally: FunctionTally, style: Style) void {
    const calls = isolate_mod.callsFor(tally.file, tally.function);
    if (calls > 0) {
        output_mod.print("{s}, {d} calls{s}", .{ style.dim(), calls, style.reset() });
    }
    const nanos = isolate_mod.timingFor(tally.file, tally.function);
    if (nanos >= std.time.ns_per_s) {
        output_mod.print("{s}, {d}.{d}s{s}", .{
            style.dim(),
            nanos / std.time.ns_per_s,
            (nanos % std.time.ns_per_s) / (std.time.ns_per_s / 10),
            style.reset(),
        });
        return;
    }
    if (nanos >= 100 * std.time.ns_per_ms) {
        output_mod.print("{s}, {d}ms{s}", .{ style.dim(), nanos / std.time.ns_per_ms, style.reset() });
    }
}

// How many calls the run made, added up from what each function's driving cost. The progress line
// counts this up while a run goes and is wiped when the report starts, so without it here the
// number a reader watched climbing is gone by the time they are told anything else.
fn callsMade() usize {
    var total: usize = 0;
    for (isolate_mod.everyTiming()) |timing| {
        total += timing.calls;
    }
    return total;
}

pub fn printTallies(tallies: []const FunctionTally, files: FileCounts, faults_injected: usize, style: Style) void {
    var covered: usize = 0;
    var paths_total: usize = 0;
    var paths_ticked: usize = 0;
    var current_file: []const u8 = "";

    output_mod.print("\n{s}Deterministic simulation{s}\n\n", .{ style.bold(), style.reset() });

    // Only the functions with something left to do, and only the first few of those. A repository
    // with hundreds of functions printed a line for every one of them, and the coverage number and
    // the checklist a reader is meant to act on ended up under six hundred lines of listing. Every
    // function is in the report file either way.
    var shown: usize = 0;
    var held_back: usize = 0;
    var finished: usize = 0;

    for (tallies) |tally| {
        const needs_work = if (tally.paths) |paths| paths.ticked != paths.total else true;
        if (!needs_work) {
            finished += 1;
        }
        if (!needs_work or shown == checklist_mod.terminal_limit) {
            if (needs_work) {
                held_back += 1;
            }
            if (tally.paths) |paths| {
                covered += 1;
                paths_total += paths.total;
                paths_ticked += paths.ticked;
            }
            continue;
        }
        shown += 1;

        if (!std.mem.eql(u8, tally.file, current_file)) {
            // A blank line between files, so a reader scanning down sees blocks rather than one
            // unbroken column. Not before the first, which would leave the report starting on a
            // gap.
            if (current_file.len != 0) {
                output_mod.print("\n", .{});
            }
            current_file = tally.file;
            output_mod.print("  {s}{s}{s}\n", .{ style.dim(), tally.file, style.reset() });
        }

        if (tally.paths) |paths| {
            covered += 1;
            paths_total += paths.total;
            paths_ticked += paths.ticked;

            const mark = if (paths.ticked == paths.total) style.pass() else style.miss();
            output_mod.print(
                "    {s} {s: <34} {s}{d}/{d} paths{s}",
                .{ mark, tally.function, style.dim(), paths.ticked, paths.total, style.reset() },
            );
            if (isolate_mod.callsFor(tally.file, tally.function) == 0 and paths.ticked == 0) {
                // A function nothing called reads as though the run tried and failed to reach its
                // paths, which is the opposite of what happened: it was never called at all, and
                // the checklist at the end says why.
                output_mod.print("{s}, never called{s}", .{ style.dim(), style.reset() });
            }
            printFunctionTime(tally, style);
            output_mod.print("\n", .{});
        } else {
            output_mod.print(
                "    {s} {s: <34} {s}no checklist{s}",
                .{ style.skip(), tally.function, style.dim(), style.reset() },
            );
            printFunctionTime(tally, style);
            output_mod.print("\n", .{});
        }
    }

    if (held_back != 0) {
        output_mod.print("\n    {s}and {d} more with paths left to reach.{s}\n", .{ style.dim(), held_back, style.reset() });
    }
    if (finished != 0) {
        output_mod.print("\n  {s}{d} function{s} covered every path, and {s} not listed above.{s}\n", .{
            style.dim(),
            finished,
            plural(finished),
            if (finished == 1) "is" else "are",
            style.reset(),
        });
    }

    const all_covered = paths_ticked == paths_total;
    const colour = if (all_covered) style.green() else style.red();
    // Every file found is accounted for on this line, tested or with nothing in it to test, so the
    // two numbers add up to the third and nothing reads as a shortfall. The second clause is left
    // out when there is nothing in it, rather than printing a zero somebody has to interpret.
    output_mod.print(
        "\n  {s}{s}Found {d} source file{s}, tested {d}{s}",
        .{ colour, style.bold(), files.found, plural(files.found), files.tested, style.reset() },
    );
    if (files.untested.len != 0) {
        // An individual test left them out on purpose, which is not the same as their having
        // nothing in them to test.
        output_mod.print(
            "{s}{s} with {d} {s}{s}",
            .{ colour, style.bold(), files.untested.len, if (isIndividualTest()) "left out" else "having nothing to test", style.reset() },
        );
    }
    output_mod.print(
        "{s}{s}, exercised {d} function{s} with {d} call{s} and executed {d} of {d} path{s}.{s}\n",
        .{ colour, style.bold(), covered, plural(covered), callsMade(), plural(callsMade()), paths_ticked, paths_total, plural(paths_total), style.reset() },
    );

    // What went wrong in those calls, which is most of what they were for. The injected count is
    // left out when nothing used an injector, rather than printing a zero that reads as "no fault
    // reached this code" when every call met a failing network.
    output_mod.print(
        "  {s}Every call ran against a network that refuses every connection, one call in {d} against an allocator that runs out, and one in {d} against a writer with almost no room.{s}\n",
        .{ style.dim(), failing_effect_every, failing_effect_every, style.reset() },
    );
    if (calls_stepped_over != 0) {
        output_mod.print(
            "  {s}Stepped over {d} call{s}, {d} of them after {d}s of processor time without returning and the rest for crashing on an input the function was never written for. The paths they would have covered are not in the count above.{s}\n",
            .{ style.dim(), calls_stepped_over, plural(calls_stepped_over), isolate_mod.stalledCount(), isolate_mod.call_processor_limit_seconds, style.reset() },
        );
    }
    if (faults_injected != 0) {
        output_mod.print(
            "  {s}{d} run{s} took an injected fault.{s}\n",
            .{ style.dim(), faults_injected, plural(faults_injected), style.reset() },
        );
    }

    // Which files those were, since a reader has to be able to check the claim: a file with nothing
    // to test declares no function for a checklist to be built from, which is a different thing
    // entirely from a function nothing exercised, and that fails the run and prints as a failure.
    // An individual test leaves files out on purpose, so they are counted rather than listed:
    // naming every file in the repository that was not asked for is longer than the report and says
    // only what the reader already asked for. Saying they declare no function would be untrue of
    // them as well, since a file full of them is left out just the same.
    if (isIndividualTest()) {
        if (files.untested.len != 0) {
            output_mod.print("    {s}{d} other file{s} left out, because this is an individual test.{s}\n", .{
                style.dim(),
                files.untested.len,
                plural(files.untested.len),
                style.reset(),
            });
        }
        return;
    }

    // Which files those were, since a reader has to be able to check the claim.
    for (files.untested) |file| {
        output_mod.print("    {s}{s} declares no function, so there is nothing in it to test.{s}\n", .{ style.dim(), file, style.reset() });
    }
}

// How many source files a run could fault test and how many held anything to fault test. Found counts
// every file read that is not the harness exercising the run; tested counts the ones that declared a
// function, which is what a checklist is built from. `untested` names the difference, borrowed from
// the sources, so the caller frees the list and nothing else.
pub const FileCounts = struct {
    found: usize,
    tested: usize,
    untested: []const []const u8,
};

pub fn countFiles(allocator: std.mem.Allocator, sources: []const SourceFile, tallies: []const FunctionTally) !FileCounts {
    var untested: std.ArrayList([]const u8) = .empty;
    errdefer untested.deinit(allocator);

    var found: usize = 0;
    for (sources) |source| {
        if (isHarness(source.source)) {
            continue;
        }
        found += 1;

        var tested = false;
        for (tallies) |tally| {
            if (std.mem.eql(u8, tally.file, source.file)) {
                tested = true;
                break;
            }
        }
        if (!tested) {
            try untested.append(allocator, source.file);
        }
    }

    return .{
        .found = found,
        .tested = found - untested.items.len,
        .untested = try untested.toOwnedSlice(allocator),
    };
}

// The last thing a run prints: where the whole report is, and then what was left out of the count
// above and why nothing could ever have put it there. Spelled out rather than left as a word to
// look up, since a reader seeing "320/320 executed" has to be told in the same breath.
pub fn printCoverageFooter(seeds_swept: usize, unobservable: usize, rounds_run: usize, report_path: []const u8, style: Style) void {
    output_mod.print(
        "  {s}Swept {d} seed{s}, with no crash and every recovery invariant holding.{s}\n",
        .{ style.dim(), seeds_swept, plural(seeds_swept), style.reset() },
    );
    if (rounds_run != 0) {
        output_mod.print(
            "  {s}Ran {d} round{s} under kcov.{s}\n",
            .{ style.dim(), rounds_run, plural(rounds_run), style.reset() },
        );
    }
    output_mod.print(
        "  {s}Full detail is in {s}.{s}\n",
        .{ style.dim(), report_path, style.reset() },
    );
    if (unobservable == 1) {
        output_mod.print(
            "\n  {s}One branch is not counted above, because no line, no annotation and no count can prove it:\n" ++
                "  a `try`, `and` or `or` has no line of its own, and the false side of an `if` whose true\n" ++
                "  side carries on has no line the true side does not share.{s}\n",
            .{ style.yellow(), style.reset() },
        );
    } else if (unobservable != 0) {
        output_mod.print(
            "\n  {s}{d} branches are not counted above, because no line, no annotation and no count can prove\n" ++
                "  them: a `try`, `and` or `or` has no line of its own, and the false side of an `if` whose\n" ++
                "  true side carries on has no line the true side does not share.{s}\n",
            .{ style.yellow(), unobservable, style.reset() },
        );
    }
    output_mod.print("\n", .{});
}

// What a package declares about its own simulation, since none of it can be worked out from here.
// A package writes one of these and nothing else: it never has an entry point of its own, never
// reads an argument, and never says where its own files live. The run does all of that once, for
// every package at the same time.
pub const Simulation = struct {

    // The seeds this package sweeps, in the order it sweeps them, so the same run does the same
    // work every time.
    seeds: []const u64,

    // Exercises every exhaustive fault exploration this package has, and returns how many of those
    // runs took a fault, for the summary.
    explore: *const fn (allocator: std.mem.Allocator) anyerror!usize,

    // Runs every scenario this package has once and returns the annotations they emitted, each
    // tagged with the module whose own simulation file emitted it, owned by the caller and freed
    // with `freeAnnotated`. Owned rather than borrowed because whatever the names were read out of
    // (a log, a recorder) dies with the call that made it, while the names are what ticks the
    // checklists afterwards.
    trace: *const fn (allocator: std.mem.Allocator) anyerror![]const Annotated,

    // Runs one seed of this package's own sweep.
    runSeed: *const fn (allocator: std.mem.Allocator, seed: u64) anyerror!void,

    // Reproduces one recorded plan, for `--replay`. Null for a package with no point-based fault
    // of its own, whose plans there are none of to replay.
    replay: ?*const fn (allocator: std.mem.Allocator, plan_text: []const u8) anyerror!void = null,

    // What the types alone already say cannot be exercised, worked out at compile time before any
    // call is made. A function whose parameter the run cannot build is never called at all, and a
    // function with no log has nowhere to send an annotation, so both of those read as unreached
    // paths in the report and neither says what to do about it. This is what says it.
    shortfalls: []const Shortfall = &.{},
};

// One reason a function was not exercised, or was exercised and could tick nothing.
pub const Shortfall = struct {
    pub const Kind = enum {
        // A parameter whose type the run cannot build, so the function is never called.
        value_factory,

        // No `Log` parameter, so the function has nowhere to send an annotation.
        log_parameter,
    };

    kind: Kind,

    // The module's path as the generated root names it, which is the same path the report groups
    // its functions under.
    module: []const u8,

    // The function's own name, which is what the report matches it against.
    function: []const u8,

    // The type a factory has to return, for a `value_factory`. Empty otherwise.
    type_name: []const u8 = "",
};

// The declaration `standard` builds. Every walk below skips it: reading its type while it is being
// built is a cycle, and the run's own entry point is not one of the things being looked for.
const simulation_declaration = "simulation";

// What a package's simulation declares, found by what each declaration is rather than by a list it
// carries: the rule the scenarios already followed, applied to the rest of what a package hands the
// run. A package writes each piece beside the module it exercises, in a `<module>.sim.zig` of its own,
// names those files in one `simulations` tuple, and `standard` below builds the whole `Simulation`
// from what the walk finds. Nothing here knows a package's own types: a scenario's subject arrives
// as whatever the package built, and the run only passes it back.
//
// Only public declarations are walked, which is what `@typeInfo` lists, so a scenario, exploration
// or seed scenario is `pub` for the run to find it at all.

// The seeds a package sweeps when it has no reason of its own to sweep others. Small enough that
// the whole sweep finishes in well under a second, while covering this many distinct starting
// points for `std.Random.Xoshiro256`. A package that finds a failing seed adds it to its own
// `pub const seeds` rather than here, since a seed that fails one package's code says nothing about
// another's.
pub const default_seeds = [_]u64{
    1,  2,  3,  4,  5,  6,  7,  8,  9,  10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30,
    31, 32,
};

// One `Failure` per field of `Enum`, so a list of what can go wrong is derived from the enum that
// already names them and can never drift from it. Every entry carries the same `err`: an injector
// only ever hands `err` back to whoever calls `check`, and a caller that has to tell one variant
// from another reads `name`, which is why this takes one error rather than one per field.
pub fn failuresFrom(comptime Enum: type, comptime err: anyerror) [@typeInfo(Enum).@"enum".fields.len]Failure {
    const fields = @typeInfo(Enum).@"enum".fields;
    var built: [fields.len]Failure = undefined;
    inline for (fields, 0..) |field, index| {
        built[index] = .{ .name = field.name, .err = err };
    }
    return built;
}

// The inverse of `failuresFrom`: a failure an injector handed back always came from that enum, so
// its name is always one of the enum's own field names and this always finds one.
pub fn nameToEnum(comptime Enum: type, name: []const u8) Enum {
    return std.meta.stringToEnum(Enum, name) orelse unreachable;
}

// What a seed scenario is handed: this run's world, an allocator, and how many seeds the sweep has,
// which is what a scenario cycling through something once per seed divides by so the sweep covers
// each of its own cases exactly once.
pub const SeedRun = struct {
    allocator: std.mem.Allocator,
    env: *Environment,
    seed_count: usize,
};

// A scenario exercised once per seed, taking the world that seed built rather than an injector: the
// clock, the randomness and anything else a seed chooses, as opposed to a fault injected by name.
pub fn isSeedScenario(comptime Function: type) bool {
    const info = @typeInfo(Function);
    if (info != .@"fn") {
        return false;
    }
    const params = info.@"fn".params;
    return params.len == 1 and params[0].type == *SeedRun;
}

// A subject `exploreAll` exercises: it takes an injector, checks its own points against it, and exercises
// the code under test through whatever came back. Found by this signature rather than by a package
// building an `ExploreSubject` around it by hand, which is the same wiring every time.
pub fn isExploration(comptime Function: type) bool {
    const info = @typeInfo(Function);
    if (info != .@"fn") {
        return false;
    }
    const params = info.@"fn".params;
    return params.len == 2 and
        params[0].type == std.mem.Allocator and
        params[1].type == *Injector;
}

// Runs every scenario this package declares, wherever it declared it, against one injector and one
// checklist. `subject` is whatever the package built, handed straight back to a scenario that names
// its own type and erased for one that takes `*anyopaque`, so a scenario never casts to read it.
// A scenario that returns an error is not the run failing: this is the trace pass, where what a
// scenario emitted is the observation and the checklists are ticked afterwards from that.
pub fn everyScenario(comptime Namespace: type, subject: anytype, injector: *Injector, checklist: *Checklist) void {
    scenariosIn(Namespace, subject, injector, checklist);
    if (@hasDecl(Namespace, "simulations")) {
        inline for (Namespace.simulations) |entry| {
            everyScenario(namespaceOf(entry), subject, injector, checklist);
        }
    }
}

// The scenarios one namespace declares itself, without descending into the files it names. Kept
// apart from `everyScenario` because the trace pass runs a namespace's own scenarios against a
// recorder of their own, which is what lets it say which module each annotation came from.
fn scenariosIn(comptime Namespace: type, subject: anytype, injector: *Injector, checklist: *Checklist) void {
    inline for (@typeInfo(Namespace).@"struct".decls) |decl| {
        if (comptime std.mem.eql(u8, decl.name, simulation_declaration)) {
            continue;
        }
        const value = @field(Namespace, decl.name);
        if (comptime isScenario(@TypeOf(value))) {
            const First = comptime @typeInfo(@TypeOf(value)).@"fn".params[0].type.?;
            if (First == *anyopaque) {
                value(@ptrCast(subject), injector, checklist) catch {};
            } else {
                value(subject, injector, checklist) catch {};
            }
        }
    }
}

// Runs every seed scenario this package declares, wherever it declared it, against one world built
// from this run's seed. Unlike the trace pass above, a failure here fails the run: a seed scenario
// asserts what has to hold for every seed.
pub fn everySeedScenario(comptime Namespace: type, run: *SeedRun) !void {
    inline for (@typeInfo(Namespace).@"struct".decls) |decl| {
        if (comptime std.mem.eql(u8, decl.name, simulation_declaration)) {
            continue;
        }
        const value = @field(Namespace, decl.name);
        if (comptime isSeedScenario(@TypeOf(value))) {
            try value(run);
        }
    }
    if (@hasDecl(Namespace, "simulations")) {
        inline for (Namespace.simulations) |entry| {
            try everySeedScenario(namespaceOf(entry), run);
        }
    }
}

// Wraps one exploration function as the `ExploreSubject` the search exercises, carrying the allocator
// function pointer has nowhere to capture.
fn Exploring(comptime exploration: anytype) type {
    return struct {
        allocator: std.mem.Allocator,

        fn run(ctx: *anyopaque, injector: *Injector) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            try exploration(self.allocator, injector);
        }

        fn subject(self: *@This()) ExploreSubject {
            return .{ .ctx = self, .run = @This().run };
        }
    };
}

// Explores every fault at every point of every exploration this package declares, and returns how
// many of those runs took a fault, for the run's summary.
pub fn everyExploration(comptime Namespace: type, allocator: std.mem.Allocator) !usize {
    var counts: ExploreCounts = .{};
    try exploreEvery(Namespace, allocator, &counts);
    return counts.injected_runs;
}

fn exploreEvery(comptime Namespace: type, allocator: std.mem.Allocator, counts: *ExploreCounts) !void {
    inline for (@typeInfo(Namespace).@"struct".decls) |decl| {
        if (comptime std.mem.eql(u8, decl.name, simulation_declaration)) {
            continue;
        }
        const value = @field(Namespace, decl.name);
        if (comptime isExploration(@TypeOf(value))) {
            var exploring: Exploring(value) = .{ .allocator = allocator };
            try exploreAll(allocator, .{
                .subject = exploring.subject(),
                .invariants = invariantsOf(Namespace),
                .counts = counts,
            });
        }
    }
    if (@hasDecl(Namespace, "simulations")) {
        inline for (Namespace.simulations) |entry| {
            try exploreEvery(namespaceOf(entry), allocator, counts);
        }
    }
}

// Reproduces one recorded plan against every exploration this package declares. The plan names the
// point it was recorded at, and an injector only fails a point the plan names, so the explorations
// the plan is not about run their clean pass and change nothing.
pub fn replayEveryExploration(comptime Namespace: type, allocator: std.mem.Allocator, plan_text: []const u8) !void {
    var parsed = Plan.parse(allocator, plan_text) catch {
        output_mod.print("\"{s}\" is not a plan this run can read.\n", .{plan_text});
        return error.InvalidArgument;
    };
    defer parsed.deinit(allocator);

    try replayEvery(Namespace, allocator, parsed);
}

fn replayEvery(comptime Namespace: type, allocator: std.mem.Allocator, parsed: Plan) !void {
    inline for (@typeInfo(Namespace).@"struct".decls) |decl| {
        if (comptime std.mem.eql(u8, decl.name, simulation_declaration)) {
            continue;
        }
        const value = @field(Namespace, decl.name);
        if (comptime isExploration(@TypeOf(value))) {
            var exploring: Exploring(value) = .{ .allocator = allocator };
            try replay(allocator, .{ .subject = exploring.subject() }, parsed);
        }
    }
    if (@hasDecl(Namespace, "simulations")) {
        inline for (Namespace.simulations) |entry| {
            try replayEvery(namespaceOf(entry), allocator, parsed);
        }
    }
}

// Whether this package has anything to replay a plan against. A package with no exploration has no
// recorded plan either, so `--replay` skips it rather than being handed one it cannot run.
fn hasExploration(comptime Namespace: type) bool {
    inline for (@typeInfo(Namespace).@"struct".decls) |decl| {
        if (comptime std.mem.eql(u8, decl.name, simulation_declaration)) {
            continue;
        }
        if (comptime isExploration(@TypeOf(@field(Namespace, decl.name)))) {
            return true;
        }
    }
    if (@hasDecl(Namespace, "simulations")) {
        inline for (Namespace.simulations) |entry| {
            if (comptime hasExploration(namespaceOf(entry))) {
                return true;
            }
        }
    }
    return false;
}

// Runs every scenario a package declares once, against one recording subject, and returns every
// annotation name they emitted. That trace is the observation: a branch that ran said so, and
// nothing has to claim it on the branch's behalf.
//
// The recorder is the package's own type and this never names it, only calls it: `init` to build
// whatever it records into, `log` for what scenarios annotate through, `names` to copy out what was
// recorded, and `deinit` to release it. The order matters and is the reason this lives here rather
// than in each package: the names have to be copied while what recorded them is still alive, and
// every package would otherwise have to get that right on its own.
//
// The recorder is built where it will live rather than returned from a call, because it wires a log
// to its own fields and a value that moved afterwards would leave that log pointing at the address
// it came from.
pub fn traceEveryScenario(comptime Namespace: type, comptime Recorder: type, allocator: std.mem.Allocator) anyerror![]const Annotated {

    var collected: std.ArrayList(Annotated) = .empty;
    errdefer {
        for (collected.items) |entry| allocator.free(entry.name);
        collected.deinit(allocator);
    }

    // The scenarios once, on the first round: they take no argument the run draws, so a second
    // round of them would reach exactly what the first did.
    if (round == 1) {
        try traceEach(Namespace, Recorder, "", allocator, &collected);
    }

    // What the types alone can reach, on top of what the scenarios exercise. Nothing here is written
    // per function: every argument comes from the signature, so a function added to a package is
    // called the moment it exists.
    const stepped_over = try exerciseEach(Namespace, Recorder, allocator, &collected);
    calls_stepped_over += stepped_over.len;
    allocator.free(stepped_over);

    return collected.toOwnedSlice(allocator);
}

// One simulation file at a time, each against a recorder of its own, so what a file's scenarios
// annotated can be told from what every other file's did. Running them all against one recorder
// would leave a module's own paths ticked by whichever scenario happened to call through it, which
// is exactly what a run must not accept: a function is covered when its own simulation exercises it.
fn traceEach(
    comptime Namespace: type,
    comptime Recorder: type,
    comptime module: []const u8,
    allocator: std.mem.Allocator,
    collected: *std.ArrayList(Annotated),
) !void {
    try traceOne(Namespace, Recorder, module, allocator, collected);

    if (@hasDecl(Namespace, "simulations")) {
        inline for (Namespace.simulations) |entry| {
            try traceEach(namespaceOf(entry), Recorder, moduleOf(entry, module), allocator, collected);
        }
    }
}

// Every module the build found, exercised from its own types with no scenario written for it, in a
// child process. Calling a function with everything its parameter types allow reaches inputs it was
// never written for, and a signature cannot say which: what makes that survivable is that a call
// which crashes or stalls costs one restart, is stepped over, and never tried again.
// Hands over a value of a type nothing can be assembled out of, by finding a function in the code
// under test that returns one and calling it against the recorder's own state.
//
// A value whose insides are function pointers cannot be built from its type: the pointers would go
// nowhere. But the repository being simulated has to make such values itself, so somewhere there is
// a function that returns one, and its argument is usually a pointer to the state it reads or
// writes. Where that state is something the recorder already holds, the run can supply it, and what
// comes back is wired to the recorder rather than to nothing. That is what reaches a function
// annotating through a value it was handed rather than through the log.
fn ValueFactoryLocator(comptime Recorder: type, comptime Namespace: type, comptime level: usize) type {
    return struct {
        const Self = @This();

        recorder: *Recorder,
        arena: std.mem.Allocator,

        // Which of the function's calls this is, and where its choices come from. A factory's state
        // is built from its type like any other value, so it needs the same two the caller uses, or
        // every call would build the state identically and a state carrying a fault to inject would
        // inject the same one forever.
        trial: usize = 0,
        random: std.Random = emptyRandom(),

        // Nothing is located at the bottom level: it exists so the level above can ask what the
        // factory can make with no locating at all, which is what stops the two chasing each other.
        const Below = if (level == 0) void else ValueFactoryLocator(Recorder, Namespace, level - 1);

        // Everywhere a factory might be declared, worked out once. These two walks cover every
        // module, helper and simulation the repository has, and every question about a type used
        // to run them again: at four modules that was most of the compile.
        const holders = helperNamespaces(Namespace) ++ helperTypes(Namespace);

        pub fn canMake(comptime T: type) bool {
            return count(T) > 0;
        }

        // How many different factories the repository has for this type. More than one is the
        // ordinary case for an interface: every implementation of it has its own, and which one a
        // run picks decides which implementation's code is reached at all.
        // Zig instantiates a generic type once per set of arguments and keeps it, so a declaration
        // inside one is computed once however often it is read. That is what stops the walks below
        // running again for every question asked about the same type.
        fn Counted(comptime T: type) type {
            return struct {
                const value = countOf(T);
            };
        }

        pub fn count(comptime T: type) usize {
            return Counted(T).value;
        }

        fn countOf(comptime T: type) usize {
            if (level == 0) {
                return 0;
            }
            comptime {
                @setEvalBranchQuota(comptime_branch_quota);
                var total: usize = 0;
                for (@typeInfo(Recorder).@"struct".fields) |field| {
                    if (hasFactory(T, field.type)) {
                        total += 1;
                    }
                }
                if (level > 1) {
                    total += factoryStates(T).len;
                }
                return total;
            }
        }

        // The `choice`th factory's value: first the ones taking state the recorder already holds,
        // then the ones taking state the factory can put together itself.
        pub fn make(self: Self, comptime T: type, choice: usize) T {
            var seen: usize = 0;
            inline for (@typeInfo(Recorder).@"struct".fields) |field| {
                if (comptime hasFactory(T, field.type)) {
                    if (seen == choice) {
                        return self.callFactory(T, field.type, &@field(self.recorder, field.name));
                    }
                    seen += 1;
                }
            }
            if (comptime level > 1) {
                inline for (comptime factoryStates(T)) |State| {
                    if (seen == choice) {
                        return self.callFactory(T, State, self.madeState(State));
                    }
                    seen += 1;
                }
            }
            unreachable;
        }

        // A state the factory can put together, made once here so the value handed back points at
        // something that outlives this call.
        // The factory call itself: the state first, then whatever else it asks for, built the same
        // way any argument is.
        fn callWithState(self: Self, comptime factory: anytype, comptime State: type, state: *State) @typeInfo(@TypeOf(factory)).@"fn".return_type.? {
            const params = @typeInfo(@TypeOf(factory)).@"fn".params;
            if (comptime params.len == 1) {
                return factory(state);
            }
            var args: std.meta.ArgsTuple(@TypeOf(factory)) = undefined;
            args[0] = state;
            var extras_made: usize = 1;
            inline for (&args, 0..) |*slot, index| {
                if (index == 0) {
                    continue;
                }
                slot.* = auto_mod.valueFactory(@TypeOf(slot.*), logTypeOf(Recorder), Below, .{
                    .locator = .{ .recorder = self.recorder, .arena = self.arena, .trial = self.trial, .random = self.random },
                    .arena = self.arena,
                    .call_allocator = self.arena,
                    .io = std.Io.failing,
                    .log = self.recorder.log(),
                    .random = self.random,
                    .recent = &throwaway_recent,
                    .literals = &.{},
                    .writer = &throwaway_writer,
                    .trial = self.trial,
                    .made = &extras_made,
                }) catch unreachable;
            }
            return @call(.auto, factory, args);
        }

        fn madeState(self: Self, comptime State: type) *State {
            const room = self.arena.create(State) catch unreachable;
            var made: usize = 1;
            room.* = auto_mod.valueFactory(State, logTypeOf(Recorder), Below, .{
                .locator = .{ .recorder = self.recorder, .arena = self.arena, .trial = self.trial, .random = self.random },
                .arena = self.arena,
                .call_allocator = self.arena,
                .io = std.Io.failing,
                .log = self.recorder.log(),
                .random = self.random,
                .recent = &throwaway_recent,
                .literals = &.{},
                .writer = &throwaway_writer,
                .trial = self.trial,
                .made = &made,
            }) catch unreachable;
            return room;
        }

        // Every state type a factory for `T` takes that the factory can put together on its own.
        fn factoryStates(comptime T: type) []const type {
            return States(T).value;
        }

        fn States(comptime T: type) type {
            return struct {
                const value = factoryStatesOf(T);
            };
        }

        fn factoryStatesOf(comptime T: type) []const type {
            comptime {
                @setEvalBranchQuota(comptime_branch_quota);
                var found: []const type = &.{};
                for (holders) |Holder| {
                    for (@typeInfo(Holder).@"struct".decls) |decl| {
                        const Function = @TypeOf(@field(Holder, decl.name));
                        const info = @typeInfo(Function);
                        if (info != .@"fn" or info.@"fn".is_generic) {
                            continue;
                        }
                        if (info.@"fn".return_type != T) {
                            continue;
                        }
                        if (info.@"fn".params.len == 0) {
                            continue;
                        }
                        const Param = info.@"fn".params[0].type orelse continue;
                        const pointer = @typeInfo(Param);
                        // `isFactory`, which is what goes on to call this, matches `*State` and not
                        // `*const State`. A const one recorded here was found and then not called,
                        // and the `unreachable` at the end of `make` took the child down with it.
                        if (pointer != .pointer or pointer.pointer.size != .one or pointer.pointer.is_const) {
                            continue;
                        }
                        const State = pointer.pointer.child;
                        if (!auto_mod.canMakeValue(State, logTypeOf(Recorder), Below)) {
                            continue;
                        }
                        // The same allowance `isFactory` makes: a factory may ask for a log or an
                        // allocator beside the state it is wired to.
                        var extras_ok = true;
                        for (info.@"fn".params[1..]) |extra| {
                            const Extra = extra.type orelse {
                                extras_ok = false;
                                break;
                            };
                            if (!auto_mod.canMakeValue(Extra, logTypeOf(Recorder), Below)) {
                                extras_ok = false;
                                break;
                            }
                        }
                        if (!extras_ok) {
                            continue;
                        }
                        var already = false;
                        for (found) |seen| {
                            if (seen == State) {
                                already = true;
                            }
                        }
                        if (!already) {
                            found = found ++ [_]type{State};
                        }
                    }
                }
                return found;
            }
        }

        fn hasFactory(comptime T: type, comptime State: type) bool {
            comptime {
                @setEvalBranchQuota(comptime_branch_quota);
                // A factory is as often a method on the state it reads as a function beside it, so
                // the types a module declares are searched as well as the module itself. Without
                // this, everything an interface is constructed from is out of reach: what makes a
                // `Log` is a method on the thing doing the logging.
                for (holders) |Holder| {
                    for (@typeInfo(Holder).@"struct".decls) |decl| {
                        if (isFactory(@TypeOf(@field(Holder, decl.name)), T, State)) {
                            return true;
                        }
                    }
                }
                return false;
            }
        }

        fn callFactory(self: Self, comptime T: type, comptime State: type, state: *State) T {
            inline for (holders) |Holder| {
                inline for (@typeInfo(Holder).@"struct".decls) |decl| {
                    const candidate = @field(Holder, decl.name);
                    if (comptime isFactory(@TypeOf(candidate), T, State)) {
                        return self.callWithState(candidate, State, state);
                    }
                }
            }
            unreachable;
        }

        // A factory takes a pointer to the state it is wired to first, returns the type wanted,
        // and takes nothing else the run cannot supply. A log to annotate through or an allocator
        // to build with is ordinary and no reason to pass it over.
        fn isFactory(comptime Function: type, comptime T: type, comptime State: type) bool {
            const info = @typeInfo(Function);
            if (info != .@"fn" or info.@"fn".is_generic or info.@"fn".is_var_args) {
                return false;
            }
            if (info.@"fn".return_type != T) {
                return false;
            }
            if (info.@"fn".params.len == 0) {
                return false;
            }
            if (info.@"fn".params[0].type != *State) {
                return false;
            }
            for (info.@"fn".params[1..]) |param| {
                const Extra = param.type orelse return false;
                if (!auto_mod.canMakeValue(Extra, logTypeOf(Recorder), Below)) {
                    return false;
                }
            }
            return true;
        }
    };
}

// How often a call gets an effect that fails: one in this many gets an allocator that runs out, and
// one in this many a writer with almost no room, on different offsets so no call gets both. Every
// call gets the failing network, which costs nothing to hand over and is what the code under test
// would meet on a machine with no route out.
pub const failing_effect_every = 4;

// How far the compiler is allowed to walk while working out what a repository declares. Every walk
// here is over types rather than values, so the cost grows with how many modules and types the
// repository has rather than with anything a run does. Raised from 60 million, which `what-changed`
// exhausted at seventeen modules.
const comptime_branch_quota = 60_000_000;

// What every wait in a exercised run does: nothing, at once.
fn returnAtOnce(userdata: ?*anyopaque, timeout: std.Io.Timeout) std.Io.Cancelable!void {
    _ = userdata;
    _ = timeout;
}

// How many calls this run stepped over: a call that killed its child, or one that produced nothing
// for long enough to be taken as stuck. Both cost the paths that call would have covered, so a run
// that steps over anything says so rather than leaving a reader to read the gap as code nothing
// exercises.
var calls_stepped_over: usize = 0;

// Somewhere for a value built while making another one to draw from. Nothing reads any of it: what
// matters about a made state is that it is whole, not what is in it.
var throwaway_recent: auto_mod.Recent = .{};
var throwaway_paper: [1024]u8 = undefined;
var throwaway_writer: std.Io.Writer = undefined;
var throwaway_prng = std.Random.Xoshiro256.init(1);
var throwaway_made: usize = 0;

fn emptyRandom() std.Random {
    return throwaway_prng.random();
}

// Every type a module declares, where a factory is as likely to live as at the module's top level.
fn helperTypes(comptime Namespace: type) []const type {
    comptime {
        @setEvalBranchQuota(comptime_branch_quota);
        var found: []const type = &.{};
        for (helperNamespaces(Namespace)) |Helper| {
            for (@typeInfo(Helper).@"struct".decls) |decl| {
                if (@TypeOf(@field(Helper, decl.name)) != type) {
                    continue;
                }
                const candidate = @field(Helper, decl.name);
                if (@typeInfo(candidate) != .@"struct") {
                    continue;
                }
                found = found ++ [_]type{candidate};
            }
        }
        return found;
    }
}

// Every namespace a factory might be declared in: the modules the build found, and the helper files
// beside them. A helper is where a repository keeps what only a test or a run needs, which is
// exactly where the thing that wires a value to a recorder lives.
fn helperNamespaces(comptime Namespace: type) []const type {
    comptime {
        @setEvalBranchQuota(comptime_branch_quota);
        var found: []const type = &.{};
        if (@hasDecl(Namespace, "modules")) {
            for (Namespace.modules) |entry| {
                found = found ++ [_]type{entry.code};
            }
        }
        if (@hasDecl(Namespace, "helpers")) {
            for (Namespace.helpers) |entry| {
                found = found ++ [_]type{entry.code};
            }
        }
        if (@hasDecl(Namespace, "simulations")) {
            for (Namespace.simulations) |entry| {
                // The simulation file itself, and then whatever it holds. A factory is as often
                // written beside a module's scenarios as beside its tests, and the user guide says
                // to put one there, so leaving this out left every factory in a `<module>.sim.zig`
                // unreachable and every function taking what it builds unexercised.
                found = found ++ [_]type{namespaceOf(entry)} ++ helperNamespaces(namespaceOf(entry));
            }
        }
        return found;
    }
}

fn AutomaticRun(comptime Namespace: type, comptime Recorder: type) type {
    return struct {
        // Two levels: what the recorder itself can supply, and on top of that what the run can
        // make and then ask for a value. Two rather than more because the second already reaches
        // everything a repository builds out of its own state, and each level costs a full walk of
        // every module at compile time.
        const Locating = ValueFactoryLocator(Recorder, Namespace, 2);

        // Which number a module path is reported under, matched against the same list the parent
        // reads back.
        fn indexOfModule(comptime module: []const u8) usize {
            comptime {
                @setEvalBranchQuota(comptime_branch_quota);
                for (modulePaths(Namespace), 0..) |candidate, index| {
                    if (std.mem.eql(u8, candidate, module)) {
                        return index;
                    }
                }
                @compileError("module not in the generated list: " ++ module);
            }
        }

        // What the child runs. It never returns a value and never unwinds: whatever it managed to
        // say reached the parent as it was said.
        fn body(plan: isolate_mod.Plan, out: isolate_mod.Emitter) void {
            var counter: usize = 0;
            exerciseNamespace(Namespace, plan, out, &counter);
            out.done();
        }

        fn exerciseNamespace(
            comptime Inner: type,
            plan: isolate_mod.Plan,
            out: isolate_mod.Emitter,
            counter: *usize,
        ) void {
            if (@hasDecl(Inner, "modules")) {
                inline for (Inner.modules) |entry| {
                    exerciseModule(entry.code, comptime indexOfModule(entry.module), entry.literals, entry.reflecting, entry.uncallable, plan, out, counter);
                }
            }
            if (@hasDecl(Inner, "simulations")) {
                inline for (Inner.simulations) |entry| {
                    exerciseNamespace(namespaceOf(entry), plan, out, counter);
                }
            }
        }

        fn exerciseModule(
            comptime Module: type,
            comptime module: usize,
            literals: []const []const u8,
            comptime reflecting: []const []const u8,
            comptime uncallable: []const []const u8,
            plan: isolate_mod.Plan,
            out: isolate_mod.Emitter,
            counter: *usize,
        ) void {
            const Log = logTypeOf(Recorder);
            // Seeded from the module and the round, so the same round of the same run draws the same
            // arguments, and a later round draws different ones for the functions it is given again.
            // The first round's seed is the one a run always had, so a run under kcov calls every
            // function with exactly the arguments a run without it does.
            var prng = std.Random.Xoshiro256.init(std.hash.Wyhash.hash(round - 1, comptime modulePaths(Namespace)[module]));

            // One thread pool for the whole module rather than one per call. Building it is what a
            // real `Io` costs, and a call that only reads a clock pays it either way, so at four
            // hundred calls a function it was the run's largest cost by far.
            var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
            defer threaded.deinit();

            // Waiting is the one thing this `Io` does not do. A duration is a number like any
            // other, so the run hands functions the same extremes it hands everything else, and a
            // retry loop told to wait a day between attempts would hold the whole run up. Returning
            // at once is also what a deterministic run wants: time passing for real is the thing
            // that makes two runs differ.
            // The network this `Io` reaches is the simulated one: no name resolves, no socket
            // opens, and every attempt fails the way a real network fails, deterministically.
            // network.zig says what that costs and why the real one cannot be handed over.
            // The filesystem is held in memory for the same reason: a function exercised hundreds of
            // times per seed that writes a file would pay a syscall on every one of them and leave
            // a directory behind whenever a call crashed part way through. filesystem.zig says what
            // it replaces and what it passes through.
            // A vtable each, rather than one written over twice: each layer copies the one under
            // it, so sharing the room would have the second copy read the table it is writing.
            var network_vtable: std.Io.VTable = undefined;
            var files_vtable: std.Io.VTable = undefined;
            var files = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer files.deinit();
            const io = filesystem_mod.install(
                network_mod.simulated(threaded.io(), &network_vtable),
                files.allocator(),
                &files_vtable,
            );
            files_vtable.sleep = returnAtOnce;

            inline for (@typeInfo(Module).@"struct".decls) |decl| {
                const value = @field(Module, decl.name);
                if (comptime (!isNamed(reflecting, decl.name) and !isNamed(uncallable, decl.name) and
                    (auto_mod.canExercise(@TypeOf(value), Log, Locating) or
                        auto_mod.canExerciseGeneric(@TypeOf(value)) or
                        auto_mod.canExerciseInvoker(@TypeOf(value)))))
                {
                    exerciseFunction(value, decl.name, module, Log, literals, io, plan, out, counter, &prng);
                }

                // A function that makes a type out of two others is instantiated with a
                // stand-in source, and what comes back is exercised like any other type: nothing
                // inside it can be reached any other way.
                if (comptime auto_mod.canExerciseTypeMaker(@TypeOf(value))) {
                    const Made = value(auto_mod.Items(auto_mod.operation_return), auto_mod.operation_return);
                    if (comptime @typeInfo(Made) == .@"struct") {
                        inline for (@typeInfo(Made).@"struct".decls) |inner| {
                            const method = @field(Made, inner.name);
                            if (comptime auto_mod.canExercise(@TypeOf(method), Log, Locating)) {
                                exerciseFunction(method, inner.name, module, Log, literals, io, plan, out, counter, &prng);
                            }
                        }
                    }
                }

                // A method on a type the module declares is one of its functions too, and the
                // report already reports them one by one. They are not in the module's own decls,
                // so they are reached through the type that holds them.
                if (comptime @TypeOf(value) == type and @typeInfo(value) == .@"struct") {
                    inline for (@typeInfo(value).@"struct".decls) |inner| {
                        const method = @field(value, inner.name);
                        if (comptime (!isNamed(reflecting, inner.name) and !isNamed(uncallable, inner.name) and
                            (auto_mod.canExercise(@TypeOf(method), Log, Locating) or
                                auto_mod.canExerciseGeneric(@TypeOf(method)) or
                                auto_mod.canExerciseInvoker(@TypeOf(method)))))
                        {
                            exerciseFunction(method, inner.name, module, Log, literals, io, plan, out, counter, &prng);
                        }
                    }
                }
            }
        }

        // One function, called with freshly drawn arguments as many times as the trial count says.
        //
        // A call that crashed is stepped over on its own, since the next draw usually lands back
        // inside what the function accepts. A call that hung is different: waiting out the stall
        // limit again for every later draw would cost more than the whole run, so one of those
        // drops the function's remaining calls.
        fn exerciseFunction(
            comptime function: anytype,
            comptime name: []const u8,
            comptime module: usize,
            comptime Log: type,
            literals: []const []const u8,
            io: std.Io,
            plan: isolate_mod.Plan,
            out: isolate_mod.Emitter,
            counter: *usize,
            prng: *std.Random.Xoshiro256,
        ) void {
            const trials = comptime auto_mod.trialsFor(@TypeOf(function), Log, Locating);
            const base = counter.*;
            counter.* += trials;

            if (plan.stalledWithin(base + 1, counter.* + 1)) {
                return;
            }
            if (plan.skippedCountWithin(base + 1, counter.* + 1) >= auto_mod.crashes_before_dropping) {
                return;
            }

            // Checked after the counter has already moved past this function's calls, so the call
            // numbers a plan is written in terms of do not shift between a complete test run and an
            // individual one. A plan from either still replays against the other.
            if (!isWanted(comptime modulePaths(Namespace)[module], name)) {
                return;
            }
            if (!isDeclaredIn(comptime modulePaths(Namespace)[module], name)) {
                return;
            }

            // Said before the first call rather than after the last, because the parent times what
            // arrives between two of these and a child that dies mid-function never gets to a line
            // it would have printed afterwards.
            out.function(comptime modulePaths(Namespace)[module], name);

            // What this function's calls have reached so far, and how many of them in a row have
            // reached nothing new. The trial count above says how rare a particular combination of
            // arguments is, which is not the same question as how many code paths the function has:
            // most functions run out of paths long before they run out of combinations, and every
            // call after that re-runs paths already covered.
            var progress_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer progress_arena.deinit();
            var progress = progress_mod.Progress.init(progress_arena.allocator());
            defer progress.deinit();
            var quiet: usize = 0;

            var trial: usize = 0;
            while (trial < trials) : (trial += 1) {
                const index = base + trial + 1;
                if (index < plan.start or plan.isSkipped(index)) {
                    continue;
                }
                out.at(index);

                // The call is given a processor-time limit of its own, because a function handed a
                // count no caller would ever pass can go round forever and nothing outside it can
                // tell that from a call that is merely slow.
                isolate_mod.startCallClock();
                const fresh = oneCall(function, name, module, Log, literals, io, out, prng.random(), trial, &progress);
                isolate_mod.stopCallClock();
                quiet = if (fresh) 0 else quiet + 1;
                if (quiet >= auto_mod.quiet_calls_before_stopping) {
                    break;
                }
            }
        }

        // One call, against a recorder of its own, with whatever it annotated reported before the
        // next call is made. Per call rather than per module, because a call that kills the child
        // must not take the annotations of the calls before it with it.
        // Says whether the call annotated anything this function's earlier calls had not, which is
        // what decides whether there is any point making another one.
        fn oneCall(
            comptime function: anytype,
            comptime name: []const u8,
            comptime module: usize,
            comptime Log: type,
            literals: []const []const u8,
            io: std.Io,
            out: isolate_mod.Emitter,
            random: std.Random,
            trial: usize,
            progress: *progress_mod.Progress,
        ) bool {
            var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena_state.deinit();
            const arena = arena_state.allocator();

            var recorder: Recorder = undefined;
            recorder.init(arena);
            defer recorder.deinit();

            var recent: auto_mod.Recent = .{};
            var made: usize = 1;

            // Somewhere to write, sometimes with barely any room. A function that reports what it
            // could not write has no other way to be asked: with room to spare, the failing side of
            // every write is unreachable.
            var paper: [4096]u8 = undefined;
            const room = if (trial % failing_effect_every == 3) @as(usize, 8) else paper.len;
            var writer = std.Io.Writer.fixed(paper[0..room]);
            throwaway_writer = std.Io.Writer.fixed(&throwaway_paper);

            // What the code under test allocates from, which fails at a different point every few
            // calls. Running out of memory is the fault every allocating function has to handle,
            // and its handling is a branch like any other: unreachable while every allocation
            // succeeds. The values built for the call come from the arena either way, so a failure
            // lands inside the code being fault tested rather than while its arguments are made.
            var failing = std.testing.FailingAllocator.init(arena, .{ .fail_index = trial / failing_effect_every });
            const call_allocator = if (trial % failing_effect_every == 1) failing.allocator() else arena;
            const ctx: auto_mod.Context(Log, Locating) = .{
                .locator = .{ .recorder = &recorder, .arena = arena, .trial = trial, .random = random },
                .arena = arena,
                .call_allocator = call_allocator,
                .io = io,
                .log = recorder.log(),
                .random = random,
                .recent = &recent,
                .literals = literals,
                .writer = &writer,
                .trial = trial,
                .made = &made,
            };

            // The run says the function was entered, rather than the function saying it. Nothing
            // else knows a call was made: the code used to open every function with an annotation
            // naming itself, which is a line per function saying what the caller already knew.
            //
            // Said here rather than after the call, because a call that crashes still entered the
            // function, and a line written afterwards would never be reached for one that did. The
            // arguments are already built by this point, so a draw that could not be made has
            // stopped before it.
            out.name(module, name ++ ":entered");

            // A generic function has no argument tuple that can be built ahead of it: the type it
            // is instantiated with is a comptime value, so the call is assembled one parameter at a
            // time instead.
            if (comptime auto_mod.canExerciseInvoker(@TypeOf(function))) {
                // Both stand-ins, so the side that handles a failure and the side that does not are
                // each reached.
                if (random.boolean()) {
                    auto_mod.callInvoker(function, auto_mod.failingCall, Log, Locating, 0, 0, 0, .{}, ctx);
                } else {
                    auto_mod.callInvoker(function, auto_mod.succeedingCall, Log, Locating, 0, 0, 0, .{}, ctx);
                }
            } else if (comptime @typeInfo(@TypeOf(function)).@"fn".is_generic) {
                var state: auto_mod.OperationState = .{ .failures_left = random.uintLessThan(usize, 4) };
                auto_mod.callGeneric(function, Log, Locating, 0, .{}, ctx, &state);
            } else {
                auto_mod.callOnce(function, Log, Locating, ctx) catch {};
            }

            const names = recorder.names(arena) catch return true;
            for (names) |annotated| {
                out.name(module, annotated);
            }
            return progress.observe(names);
        }
    };
}

// Every module path the build listed, in the order the walk reaches them, so a child can name one
// with a number and the parent can put the path back without either owning the text.
fn modulePaths(comptime Namespace: type) []const []const u8 {
    comptime {
        @setEvalBranchQuota(comptime_branch_quota);
        var found: []const []const u8 = &.{};
        if (@hasDecl(Namespace, "modules")) {
            for (Namespace.modules) |entry| {
                found = found ++ [_][]const u8{entry.module};
            }
        }
        if (@hasDecl(Namespace, "simulations")) {
            for (Namespace.simulations) |entry| {
                found = found ++ modulePaths(namespaceOf(entry));
            }
        }
        return found;
    }
}

// Exercises every module automatically and puts what they annotated into `collected`. Whatever had to
// be stepped over is reported, so the run can say which calls it could not make rather than leaving
// their paths looking simply unreached.
fn exerciseEach(
    comptime Namespace: type,
    comptime Recorder: type,
    allocator: std.mem.Allocator,
    collected: *std.ArrayList(Annotated),
) ![]const usize {
    var lines: std.ArrayList([]const u8) = .empty;
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    const skipped = try isolate_mod.exerciseUntilDone(AutomaticRun(Namespace, Recorder).body, &lines, allocator);

    const paths = comptime modulePaths(Namespace);
    for (lines.items) |line| {
        const split = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const which = std.fmt.parseInt(usize, line[0..split], 10) catch continue;
        if (which >= paths.len) {
            continue;
        }
        try collected.append(allocator, .{
            .module = paths[which],
            .name = try allocator.dupe(u8, line[split + 1 ..]),
            .from_runner = true,
        });
    }

    return skipped;
}

// The scenarios one namespace declares itself, run against a fresh recorder, with everything they
// annotated tagged as this module's.
fn traceOne(
    comptime Namespace: type,
    comptime Recorder: type,
    comptime module: []const u8,
    allocator: std.mem.Allocator,
    collected: *std.ArrayList(Annotated),
) !void {
    var recorder: Recorder = undefined;
    recorder.init(allocator);
    defer recorder.deinit();

    // The same `Io` the runner hands a function it calls itself: a filesystem held in memory and a
    // network that refuses. A scenario writes files, so without this the trace pass is the one part
    // of a run that reaches the real disk.
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    var network_vtable: std.Io.VTable = undefined;
    var files_vtable: std.Io.VTable = undefined;
    var files = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer files.deinit();
    const io = filesystem_mod.install(
        network_mod.simulated(threaded.io(), &network_vtable),
        files.allocator(),
        &files_vtable,
    );

    // Emptied before these scenarios rather than after, so a module never starts on top of what the
    // last one wrote and a run stays the same whichever order the modules came in.
    filesystem_mod.clear();

    var subject: Subject(logTypeOf(Recorder)) = .{ .allocator = allocator, .log = recorder.log(), .io = io };

    var injector = Injector.initRecording(allocator);
    defer injector.deinit();

    var throwaway = try emptyChecklist(allocator);
    defer throwaway.deinit();

    scenariosIn(Namespace, &subject, &injector, &throwaway);

    // The names are the recorder's to hand over and this list's to keep: the slice they arrived in
    // is released here either way, and each name moves into `collected`, which owns it from then on.
    const names = try recorder.names(allocator);
    defer allocator.free(names);
    errdefer for (names) |name| allocator.free(name);

    for (names) |name| {
        try collected.append(allocator, .{ .module = module, .name = name });
    }
}

// What every scenario is handed: an allocator for a scenario that builds a result of its own, and
// the log the run reads annotations back off. Both are the same for every package, so this is the
// framework's rather than each package's, and the log type is a parameter because what a log is
// belongs to the repository being simulated and never to this file.
//
// A scenario names `sim.Subject(Log)` in its own signature. Zig gives the same type back for the
// same argument, so every scenario in a package is talking about one type however many files they
// are spread across.
pub fn Subject(comptime Log: type) type {
    return struct {
        allocator: std.mem.Allocator,

        // The log every scenario annotates through, so what the code emits while a scenario runs
        // lands in one place the run can read afterwards.
        log: Log,

        // The `Io` to exercise the code under test with. Its filesystem is held in memory and its
        // network refuses every connection, so a scenario that writes a file costs no syscall and
        // leaves nothing behind. A scenario that builds its own `Io` instead reaches the real disk,
        // which is what this field exists to stop.
        io: std.Io,
    };
}
// Every function the types alone already say cannot be exercised, or cannot tick anything, for every
// module the generated root found. Worked out here rather than while exercising because it is a fact
// about the signatures: nothing has to run for it to be true, and a function that is never called
// would otherwise leave the report saying only that its paths went unreached.
fn shortfallsOf(comptime Namespace: type, comptime Recorder: type) []const Shortfall {
    comptime {
        @setEvalBranchQuota(comptime_branch_quota);
        var found: []const Shortfall = &.{};
        found = found ++ shortfallsIn(Namespace, Namespace, Recorder);
        return found;
    }
}

fn shortfallsIn(comptime Root: type, comptime Inner: type, comptime Recorder: type) []const Shortfall {
    comptime {
        @setEvalBranchQuota(comptime_branch_quota);
        var found: []const Shortfall = &.{};
        if (@hasDecl(Inner, "modules")) {
            for (Inner.modules) |entry| {
                found = found ++ shortfallsInModule(Root, entry.code, entry.module, entry.reflecting, Recorder);
            }
        }
        if (@hasDecl(Inner, "simulations")) {
            for (Inner.simulations) |entry| {
                found = found ++ shortfallsIn(Root, namespaceOf(entry), Recorder);
            }
        }
        return found;
    }
}

fn shortfallsInModule(
    comptime Root: type,
    comptime Module: type,
    comptime module: []const u8,
    comptime reflecting: []const []const u8,
    comptime Recorder: type,
) []const Shortfall {
    comptime {
        @setEvalBranchQuota(comptime_branch_quota);
        const Log = logTypeOf(Recorder);
        const Locating = ValueFactoryLocator(Recorder, Root, 2);
        var found: []const Shortfall = &.{};
        if (@typeInfo(Module) != .@"struct") {
            return found;
        }
        for (@typeInfo(Module).@"struct".decls) |decl| {
            // A function the walk found reflecting on its own type parameter is not exercised, so
            // nothing is asked for it either: what it needs is not an annotation or a factory.
            if (isNamed(reflecting, decl.name)) {
                continue;
            }
            found = found ++ shortfallOf(@TypeOf(@field(Module, decl.name)), decl.name, module, Log, Locating);

            // A method on a type the module declares is one of its functions too, reached the same
            // way the exercising reaches it.
            if (@TypeOf(@field(Module, decl.name)) == type) {
                const declared = @field(Module, decl.name);
                if (@typeInfo(declared) == .@"struct") {
                    for (@typeInfo(declared).@"struct".decls) |inner| {
                        if (isNamed(reflecting, inner.name)) {
                            continue;
                        }
                        found = found ++ shortfallOf(@TypeOf(@field(declared, inner.name)), inner.name, module, Log, Locating);
                    }
                }
            }
        }
        return found;
    }
}

// Whether a name is one of a list. The list is the walk's answer about one module's source, and
// every place that decides what to do with a declaration asks it the same way.
pub fn isNamed(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| {
        if (std.mem.eql(u8, candidate, name)) {
            return true;
        }
    }
    return false;
}

fn shortfallOf(
    comptime Function: type,
    comptime name: []const u8,
    comptime module: []const u8,
    comptime Log: type,
    comptime Locating: type,
) []const Shortfall {
    comptime {
        if (@typeInfo(Function) != .@"fn") {
            return &.{};
        }
        if (auto_mod.canExercise(Function, Log, Locating) or
            auto_mod.canExerciseGeneric(Function) or
            auto_mod.canExerciseInvoker(Function))
        {
            // It can be called. Whether anything it does can be seen is the other question.
            if (!auto_mod.takesLog(Function, Log)) {
                return &[_]Shortfall{.{ .kind = .log_parameter, .module = module, .function = name }};
            }
            return &.{};
        }
        if (auto_mod.firstUnbuildableParameter(Function, Log, Locating)) |Unbuildable| {
            return &[_]Shortfall{.{
                .kind = .value_factory,
                .module = module,
                .function = name,
                .type_name = @typeName(Unbuildable),
            }};
        }
        return &.{};
    }
}

// The recorder a package declares, wherever it declared it, or the framework's when it declares
// none. Found by name because a type is not a signature and there is nothing else to recognise it
// by; a package declares at most one.
fn recorderTypeOf(comptime Namespace: type) type {
    if (@hasDecl(Namespace, "Recorder")) {
        return Namespace.Recorder;
    }
    if (@hasDecl(Namespace, "simulations")) {
        inline for (Namespace.simulations) |entry| {
            if (comptime hasRecorder(namespaceOf(entry))) {
                return recorderTypeOf(namespaceOf(entry));
            }
        }
    }
    return DefaultRecorder;
}

fn hasRecorder(comptime Namespace: type) bool {
    if (@hasDecl(Namespace, "Recorder")) {
        return true;
    }
    if (@hasDecl(Namespace, "simulations")) {
        inline for (Namespace.simulations) |entry| {
            if (comptime hasRecorder(namespaceOf(entry))) {
                return true;
            }
        }
    }
    return false;
}

// What a package's log is, read off its recorder's own `log` rather than named here, which is what
// keeps this file free of any package's types.
fn logTypeOf(comptime Recorder: type) type {
    return @typeInfo(@TypeOf(Recorder.log)).@"fn".return_type.?;
}

// What has to hold after every injected run, where a package says so. Found by name, the way the
// seeds are, because an invariant is a value rather than a signature and there is nothing else to
// recognise one by. A package that registers none is checked for nothing beyond not crashing.
fn invariantsOf(comptime Namespace: type) []const Invariant {
    if (@hasDecl(Namespace, "invariants")) {
        // Taken by reference, because a package writes an array literal rather than a slice and an
        // array does not coerce to one on its own.
        return &Namespace.invariants;
    }
    return &.{};
}

// The seeds this package sweeps: its own where it names them, the shared sweep otherwise.
fn seedsOf(comptime Namespace: type) []const u64 {
    if (@hasDecl(Namespace, "seeds")) {
        return Namespace.seeds;
    }
    return &default_seeds;
}

// A checklist with nothing on it, for the trace pass, where what a scenario emitted is the
// observation and no path is ticked. Built here rather than in each package, since a package has
// no reason to know what an empty one looks like.
pub fn emptyChecklist(allocator: std.mem.Allocator) !Checklist {
    return .{
        .allocator = allocator,
        .file = try allocator.dupe(u8, "trace"),
        .function = try allocator.dupe(u8, "trace"),
        .paths = try allocator.alloc(CoveragePath, 0),
        .ticked = try allocator.alloc(bool, 0),
    };
}

// Builds a package's whole `Simulation` from what it declared: every scenario, every exploration and
// every seed scenario the walk found, and its own seeds if it named any and the shared sweep
// otherwise. A package that needs something this cannot express writes the `Simulation` literal
// itself; nothing here is required.
pub fn standard(comptime Namespace: type) Simulation {
    // A project that declares a recorder of its own is fault tested through its own log type. One that
    // declares none gets the framework's, which records through the annotation channel.
    const Recorder = recorderTypeOf(Namespace);
    const Runner = struct {
        fn explore(allocator: std.mem.Allocator) anyerror!usize {
            return everyExploration(Namespace, allocator);
        }

        fn trace(allocator: std.mem.Allocator) anyerror![]const Annotated {
            return traceEveryScenario(Namespace, Recorder, allocator);
        }

        fn runSeed(allocator: std.mem.Allocator, seed: u64) anyerror!void {
            var env = Environment.fromSeed(seed);
            var run: SeedRun = .{ .allocator = allocator, .env = &env, .seed_count = seedsOf(Namespace).len };
            try everySeedScenario(Namespace, &run);
        }

        fn replayPlan(allocator: std.mem.Allocator, plan_text: []const u8) anyerror!void {
            return replayEveryExploration(Namespace, allocator, plan_text);
        }
    };

    return .{
        .seeds = seedsOf(Namespace),
        .explore = Runner.explore,
        .trace = Runner.trace,
        .runSeed = Runner.runSeed,
        .replay = if (comptime hasExploration(Namespace)) Runner.replayPlan else null,
        .shortfalls = comptime shortfallsOf(Namespace, Recorder),
    };
}

// One package the build found, and what it declared. `directory` comes from the build's own scan
// of the repository rather than from the package: a package that had to write down where it lives
// would be wrong the day it moved, and nothing would fail.
pub const Package = struct {
    directory: []const u8,
    simulation: Simulation,

    // Directory names the walk below this package never descends into, from what the build was told
    // to leave out. The build uses the same list to decide what to compile in, and the walk needs it
    // too: a directory left out of the compile but walked here puts files on the checklist that
    // nothing was ever built to exercise.
    excluded_directories: []const []const u8 = &.{},
};

// Where the full report is written when nothing says otherwise: gitignored and machine-local,
// relative to the repository root, since that is where the run starts.
pub const default_report_path = "tmp/sim-coverage-report.txt";

// One run in progress: what was read once at the top and is shared by everything after it. One
// run covers every package the build found, and each function is checked against what its own
// module's simulation file annotated.
pub const Run = struct {
    allocator: std.mem.Allocator,

    // Where this run writes its full checklist, taken from the arguments it was started with.
    report_path: []const u8,

    // Every seed every package sweeps, added up, for the summary line.
    seeds_swept: usize,

    // How many runs this simulation injected a fault into, for the summary. Per function it cannot
    // be said: a fault is injected in the simulation's own code, not in the function it exercises, so
    // attributing one to a function would mean naming that function by hand.
    faults_injected: usize = 0,

    sources: []SourceFile,
    style: Style,
    exercised: []Exercised,
    tallies: []FunctionTally,
    report_text: std.Io.Writer.Allocating,
    coverage: Coverage,

    // One checklist per entry of `exercised`, built once from the source and ticked as the run goes:
    // by lines after every round under kcov, and by annotations. Empty for a worker, which only
    // exercises and never reads coverage.
    checklists: []Checklist,

    // How many rounds ran under kcov. Zero when kcov was not used.
    rounds_run: usize = 0,

    pub fn deinit(self: *Run) void {
        self.coverage.deinit();
        self.report_text.deinit();
        freeChecklists(self.allocator, self.checklists);
        self.allocator.free(self.tallies);
        freeExercised(self.allocator, self.exercised);
        freeSources(self.allocator, self.sources);
    }
};

// Reads every package's sources once, decides colour once, and builds the function list and the
// tallies from what those sources declare. Reading each file once is what keeps a run
// deterministic: a file changing under a run would otherwise be seen differently by two readers.
pub fn startRun(allocator: std.mem.Allocator, init: std.process.Init.Minimal, args: Args, packages: []const Package) !Run {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // The run starts in a scratch directory of its own, so each package is read at the repository
    // it was found in rather than under wherever the run happens to be standing.
    const sources = try readEverySource(allocator, io, args.repository, packages);
    errdefer freeSources(allocator, sources);

    const stderr_is_tty = std.Io.File.stderr().isTty(io) catch false;
    const style = Style.init(stderr_is_tty and !args.no_color and !(init.environ.contains(allocator, "NO_COLOR") catch false));

    // The progress lines are for a person waiting on a slow run. Nothing is waiting on a run whose
    // output is a file, so there they are only noise wrapped around the report.
    isolate_mod.progress_is_watched = stderr_is_tty;

    // Set before anything is exercised and before the function list is built, because both read it.
    only_file = args.only_file;
    only_function = args.only_function;
    if (isIndividualTest() and !args.worker) {
        printIndividualTest(style);
    }

    const exercised = try everyFunction(allocator, sources);
    if (isIndividualTest() and exercised.len == 0) {
        // Otherwise the run reports full coverage of nothing at all and exits zero, which reads as
        // a pass for a file or a function that does not exist.
        output_mod.print("Nothing here matches what was asked for, so there is nothing to fault test.\n", .{});
        // `sources` is released by the `errdefer` above. Releasing it here as well was a double
        // free that took the process down instead of printing the sentence above.
        allocator.free(exercised);
        return error.NothingMatched;
    }
    errdefer freeExercised(allocator, exercised);
    // Read by the runner, which otherwise exercises everything the compiled module holds rather than
    // everything the file wrote.
    declared_in_source = exercised;
    const tallies = try initialTallies(allocator, exercised);

    var seeds_swept: usize = 0;
    for (packages) |package| {
        seeds_swept += package.simulation.seeds.len;
    }

    // A worker exercises and hands over; it never reads coverage, so it never builds a checklist.
    const checklists = if (args.worker) try allocator.alloc(Checklist, 0) else try buildChecklists(allocator, exercised, sources);

    return .{
        .allocator = allocator,
        .report_path = args.report_path,
        .seeds_swept = seeds_swept,
        .sources = sources,
        .style = style,
        .exercised = exercised,
        .tallies = tallies,
        .report_text = .init(allocator),
        .coverage = .{ .allocator = allocator },
        .checklists = checklists,
    };
}

// Builds every checklist, ticks it from what the run annotated, checks that every declaration the
// repository holds was fault tested at all, and writes the whole report to `report_path`. A failing run
// prints that report as well, since what failed is exactly what a person needs and pointing them at
// a file for it would be one step too many.
pub fn checkCoverage(run: *Run, annotated: []const Annotated) !void {
    const accounting: AccountingOptions = .{ .source_files = run.sources, .registered = run.tallies };
    var coverage_error: ?anyerror = null;
    run.coverage = blk: {
        tickChecklistsFromTrace(run.allocator, run.checklists, run.exercised, annotated) catch |err| {
            coverage_error = err;
            break :blk Coverage{ .allocator = run.allocator };
        };
        break :blk summariseCoverage(run.allocator, run.checklists, run.exercised, run.tallies, &run.report_text) catch |err| {
            coverage_error = err;
            break :blk Coverage{ .allocator = run.allocator };
        };
    };

    var enumeration_error: ?anyerror = null;
    // Skipped on an individual test. This check exists to catch the tool quietly failing to notice
    // a declaration, and it decides that by finding every declaration in every source file in the
    // function list. On a run asked for one file or one function, everything else is absent because
    // it was asked to be, so the check would fail the run for doing what it was told.
    if (coverage_error == null and !isIndividualTest()) {
        const accounted = checkEveryDeclarationAccountedFor(run.allocator, accounting, &run.report_text) catch |err| blk: {
            enumeration_error = err;
            break :blk false;
        };
        if (enumeration_error == null and !accounted) {
            enumeration_error = error.SimCoverageEnumerationIncomplete;
        }
    }

    var threaded = std.Io.Threaded.init(run.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    if (std.fs.path.dirname(run.report_path)) |parent| {
        try std.Io.Dir.cwd().createDirPath(io, parent);
    }
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = run.report_path, .data = run.report_text.written() });

    if (coverage_error != null or enumeration_error != null) {
        // The report itself, not a copy of it on the terminal. It runs to thousands of lines
        // against a repository that has never been annotated, and printing it buries the coverage
        // number and the checklist that a reader is meant to start from.
        output_mod.print("\n  Every branch, ticked and unticked, is in {s}.\n", .{run.report_path});
    }
    if (coverage_error) |err| {
        return err;
    }
    if (enumeration_error) |err| {
        return err;
    }
}

// The summary, then the exit status: every function and what it covered, what the run swept, where
// the detail is, what nothing could observe, and finally the paths nothing reached, which are what
// end the run red.
// Says in words whether the run passed or failed, and why it failed.
//
// The percentage above it is a number, and a reader who does not already know that anything under
// a hundred is a failure reads a red run and a green one as the same thing with different numbers.
// This is the line that tells them, and it is the last thing before the duration because the end of
// a run is where somebody looks for the answer.
fn printVerdict(ticked: usize, total: usize, unreached: usize, style: Style) void {
    if (unreached != 0) {
        output_mod.print("  {s}Failed: {d} code path{s} of {d} {s} never reached.{s}\n", .{
            style.red(),
            unreached,
            plural(unreached),
            total,
            if (unreached == 1) "was" else "were",
            style.reset(),
        });
        output_mod.print("  {s}The list above says what to do about each one.{s}\n", .{ style.dim(), style.reset() });
        return;
    }
    if (checklist_mod.percentageOf(ticked, total) != 100) {
        // Every path that carries an annotation was reached, and the number is still short. What is
        // missing is a path nothing could reach at all, because the function holding it could not
        // be called, so there is no unreached path to name.
        output_mod.print("  {s}Failed: not every code path could be reached.{s}\n", .{ style.red(), style.reset() });
        output_mod.print("  {s}The list above says what each one needs.{s}\n", .{ style.dim(), style.reset() });
        return;
    }
    output_mod.print("  {s}Passed: every code path ran.{s}\n", .{ style.green(), style.reset() });
}

pub fn reportRun(run: *Run, elapsed_ns: i96, packages: []const Package) !void {

    const files = try countFiles(run.allocator, run.sources, run.tallies);
    defer run.allocator.free(files.untested);

    printTallies(run.tallies, files, run.faults_injected, run.style);
    printCoverageFooter(run.seeds_swept, run.coverage.unobservable, run.rounds_run, run.report_path, run.style);
    printUntickedPaths(run.coverage.unticked.items, run.style, run.report_path);

    const items = try buildChecklistItems(run, packages);
    defer freeChecklistItems(run.allocator, items);
    checklist_mod.print(items, run.style, run.report_path);

    const counts = pathCounts(run.tallies);
    checklist_mod.printCoverage(counts.ticked, counts.total, run.style);
    printVerdict(counts.ticked, counts.total, run.coverage.unticked.items.len, run.style);

    // Last, under the verdict and the one number, because a reader looks at the end of a run for
    // those and anything printed after them is what pushes them off the screen. It sat above the
    // checklist, which on a repository with work outstanding is a page of it.
    printElapsed(elapsed_ns, run.style);

    if (run.coverage.unticked.items.len != 0) {
        return error.SimCoveragePathsUnticked;
    }
    // The one number decides the exit status, so a run that reached everything it could still ends
    // red when something it could not call left a path unreachable.
    if (checklist_mod.percentageOf(counts.ticked, counts.total) != 100) {
        return error.SimCoverageIncomplete;
    }
}

// How many paths a run could tick and how many it did, added up across every function. Unobservable
// branches are in neither, since `total` already counts only what a run can tick.
pub fn pathCounts(tallies: []const FunctionTally) struct { ticked: usize, total: usize } {
    var ticked: usize = 0;
    var total: usize = 0;
    for (tallies) |tally| {
        if (tally.paths) |paths| {
            ticked += paths.ticked;
            total += paths.total;
        }
    }
    return .{ .ticked = ticked, .total = total };
}

// Turns what the run found into the list of things to do: one line per unticked path, and one per
// function the types alone say could not be exercised. Every line carries a file and a line, which
// means looking each function's declaration up in the source the run already read.
//
// The caller owns what comes back, and `freeChecklistItems` releases it.
pub fn buildChecklistItems(run: *Run, packages: []const Package) ![]const checklist_mod.Item {
    var items: std.ArrayList(checklist_mod.Item) = .empty;
    errdefer freeChecklistItemList(run.allocator, &items);

    // The functions a missing factory stops being called at all. Their paths went unreached because
    // nothing called them, so naming each of those paths as well would be several lines asking for
    // work that writing the factory is the whole of.
    var uncallable: std.ArrayList(struct { module: []const u8, function: []const u8 }) = .empty;
    defer uncallable.deinit(run.allocator);

    for (packages) |package| {
        for (package.simulation.shortfalls) |shortfall| {
            const line = declarationLineOf(run, shortfall.module, shortfall.function) orelse continue;
            switch (shortfall.kind) {
                .value_factory => {
                    // Only worth saying when the function really was never called: a function the
                    // run reached some other way has no factory missing.
                    if (isolate_mod.callsFor(shortfall.module, shortfall.function) != 0) {
                        continue;
                    }
                    // And only when it cost something. A function a scenario exercises is never called
                    // by the runner, so the test above passes it; with every path of it ticked, a
                    // factory would change nothing, and asking for one is asking for work already
                    // done.
                    if (untickedPathsOf(run, shortfall.module, shortfall.function) == 0) {
                        continue;
                    }
                    try uncallable.append(run.allocator, .{ .module = shortfall.module, .function = shortfall.function });
                    try items.append(run.allocator, .{
                        .kind = .value_factory,
                        .file = try run.allocator.dupe(u8, shortfall.module),
                        .line = line,
                        .function = try run.allocator.dupe(u8, shortfall.function),
                        .type_name = try run.allocator.dupe(u8, shortfall.type_name),
                    });
                },
                .log_parameter => {
                    // Only worth saying when it cost something: a function with no branch to
                    // annotate loses nothing by having nowhere to send one, and a path a line
                    // proves needs no annotation, so only the paths no line can prove count.
                    const paths = annotationOnlyPathsOf(run, shortfall.module, shortfall.function);
                    if (paths == 0) {
                        continue;
                    }
                    try items.append(run.allocator, .{
                        .kind = .log_parameter,
                        .file = try run.allocator.dupe(u8, shortfall.module),
                        .line = line,
                        .function = try run.allocator.dupe(u8, shortfall.function),
                        .paths = paths,
                    });
                },
            }
        }
    }

    // A loop's three paths all want the same two annotations, so one line covers them: a line per
    // path would say the same thing three times about one loop.
    var loops_named: std.ArrayList(struct { file: []const u8, line: u32 }) = .empty;
    defer loops_named.deinit(run.allocator);

    for (run.coverage.unticked.items) |path| {
        var skip = false;
        for (uncallable.items) |stopped| {
            if (std.mem.eql(u8, stopped.module, path.file) and std.mem.eql(u8, stopped.function, path.function)) {
                skip = true;
            }
        }
        if (skip) {
            continue;
        }

        // A path with a line of its own that the build has code for was reachable and not reached,
        // whatever its name says: that is a scenario's job, the same as an annotated branch no call
        // reached.
        const where = if (path.witness != null and !path.line_missing) null else try checklist_mod.whereItGoes(run.allocator, path.name);
        if (where) |text| {
            if (path.line_missing) {
                try items.append(run.allocator, .{
                    .kind = .line_table,
                    .file = try run.allocator.dupe(u8, path.file),
                    .line = path.line,
                    .function = try run.allocator.dupe(u8, path.function),
                    .where = text,
                });
                continue;
            }
            if (std.mem.startsWith(u8, path.name, "loop:")) {
                var already = false;
                for (loops_named.items) |seen| {
                    if (seen.line == path.line and std.mem.eql(u8, seen.file, path.file)) {
                        already = true;
                        break;
                    }
                }
                if (already) {
                    run.allocator.free(text);
                    continue;
                }
                try loops_named.append(run.allocator, .{ .file = path.file, .line = path.line });
            }
            try items.append(run.allocator, .{
                .kind = .annotation,
                .file = try run.allocator.dupe(u8, path.file),
                .line = path.line,
                .function = try run.allocator.dupe(u8, path.function),
                .name = try run.allocator.dupe(u8, path.name),
                .where = text,
                // The false side of an `if` with no `else` has no body to move: what proves it is
                // the true side's annotation, counted against the function's entries.
                .counting = !path.marker_room and std.mem.endsWith(u8, path.name, ":false"),
            });
            continue;
        }
        try items.append(run.allocator, .{
            .kind = .scenario,
            .file = try run.allocator.dupe(u8, path.file),
            .line = path.line,
            .function = try run.allocator.dupe(u8, path.function),
            .name = try run.allocator.dupe(u8, path.name),
        });
    }

    return items.toOwnedSlice(run.allocator);
}

// Which line a function is declared on, read from the source the run already holds. Null when the
// module was not one of the files read, which is how a function reached through a type the run
// instantiated rather than a file it read is left off the list rather than reported at line zero.
fn declarationLineOf(run: *Run, module: []const u8, function_name: []const u8) ?u32 {
    for (run.sources) |source| {
        if (!std.mem.eql(u8, source.file, module)) {
            continue;
        }
        const declarations = coverage_mod.listDeclarations(run.allocator, source.source) catch return null;
        defer coverage_mod.freeDeclarations(run.allocator, declarations);
        for (declarations) |declaration| {
            if (std.mem.eql(u8, declaration.name, function_name)) {
                return declaration.line;
            }
        }
        return null;
    }
    return null;
}

// How many of one function's paths went unticked, which is what a missing log costs it.
// How many of a function's unticked paths only an annotation can prove: no line of their own, or a
// line the build carried no code for. These are what a missing `Log` parameter costs.
fn annotationOnlyPathsOf(run: *Run, module: []const u8, function_name: []const u8) usize {
    var count: usize = 0;
    for (run.coverage.unticked.items) |path| {
        if (!std.mem.eql(u8, path.file, module) or !std.mem.eql(u8, path.function, function_name)) {
            continue;
        }
        if (path.witness == null or path.line_missing) {
            count += 1;
        }
    }
    return count;
}

fn untickedPathsOf(run: *Run, module: []const u8, function_name: []const u8) usize {
    for (run.tallies) |tally| {
        if (!std.mem.eql(u8, tally.file, module) or !std.mem.eql(u8, tally.function, function_name)) {
            continue;
        }
        const paths = tally.paths orelse return 0;
        return paths.total - paths.ticked;
    }
    return 0;
}

pub fn freeChecklistItems(allocator: std.mem.Allocator, items: []const checklist_mod.Item) void {
    for (items) |item| {
        allocator.free(item.file);
        allocator.free(item.function);
        allocator.free(item.name);
        allocator.free(item.where);
        allocator.free(item.type_name);
    }
    allocator.free(items);
}

fn freeChecklistItemList(allocator: std.mem.Allocator, items: *std.ArrayList(checklist_mod.Item)) void {
    freeChecklistItems(allocator, items.items);
    items.* = .empty;
}

// How long the whole run took, so a reader can tell a run that got slower from one that always cost
// this much. It is wall clock, and it is the one number here that is different on every machine and
// every run: nothing reads it back, and no part of the simulation is decided by it.
fn printElapsed(elapsed_ns: i96, style: Style) void {
    const seconds: u64 = @intCast(@divTrunc(@max(elapsed_ns, 0), std.time.ns_per_s));
    if (seconds < 60) {
        output_mod.print("  {s}Took {d}s.{s}\n", .{ style.dim(), seconds, style.reset() });
        return;
    }
    output_mod.print("  {s}Took {d}m {d}s.{s}\n", .{ style.dim(), seconds / 60, seconds % 60, style.reset() });
}

// Every name a run's annotations carry, in the order they were emitted, which is what ticks the
// checklists. Takes the entries as a slice of anything with a `message` field, so the collector
// itself stays with the package whose log type it is built from. Each name is copied, because what
// the entries point into dies with the scenario that emitted them while the names are read long
// afterwards; `freeNames` is what releases them.
pub fn annotatedNames(allocator: std.mem.Allocator, entries: anytype) ![]const []const u8 {
    const names = try allocator.alloc([]const u8, entries.len);
    var written: usize = 0;
    errdefer {
        for (names[0..written]) |name| allocator.free(name);
        allocator.free(names);
    }
    for (entries) |entry| {
        names[written] = try allocator.dupe(u8, entry.message);
        written += 1;
    }
    return names;
}

// Releases what `annotatedNames`, or any other `Simulation.trace`, handed back.
pub fn freeNames(allocator: std.mem.Allocator, names: []const []const u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

// The whole run, for every package the build found: one coverage reading over every package's
// sources at once, each function checked against what its own module's simulation file annotated.
//
// This is the entry point the generated root file calls, and the only one there is. A package has
// no `main` of its own: it declares a `Simulation` and nothing else, so adding a package adds no
// argument parsing, no report, no exit status and no second way to run a simulation.
// Prints an error that stopped the run, and nothing for the ones that are the run's own answer.
//
// A red run is how this tool reports work outstanding, and the report has already said all of it in
// sentences somebody can act on, so those errors' names add nothing and printing one pushes the
// duration and the coverage number up off the end. Anything else stopped the run rather than being
// its answer, and exiting on that silently would leave nobody anything to go on.
pub fn printUnexpectedError(err: anyerror) void {
    switch (err) {
        error.SimCoveragePathsUnticked,
        error.SimCoverageIncomplete,
        error.NothingMatched,
        // The worker printed its own failure, and the round loop said which round it was in.
        error.WorkerFailed,
        => {},
        else => output_mod.print("The run stopped with {t}.\n", .{err}),
    }
}

// The panic handler every generated root installs, and the entry point it aliases. Both are the
// same in every project, so they live here rather than being written into each generated root.
pub const panic = std.debug.FullPanic(panicQuietlyInChild);

// The `main` for one generated root, which is the only thing that differs: the packages it found.
pub fn mainFor(comptime Root: type) fn (std.process.Init.Minimal) u8 {
    return struct {
        fn main(init: std.process.Init.Minimal) u8 {
            runRepository(init, &Root.packages) catch |err| {
                printUnexpectedError(err);
                return 1;
            };
            return 0;
        }
    }.main;
}

pub fn runRepository(init: std.process.Init.Minimal, packages: []const Package) !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer std.debug.assert(debug_allocator.deinit() == .ok);
    const allocator = debug_allocator.allocator();

    const args = try parseArgs(init.args);

    // `--replay` reproduces a failure the ordinary run already reported, so it runs a strict subset
    // of what follows and then stops. The text says which parts to run: a seed runs that seed's
    // scenarios, injections replay the explorations that carry those points, and a plan holding
    // both runs both.
    if (args.replay_plan) |plan_text| {
        var plan = try plan_mod.Plan.parse(allocator, plan_text);
        defer plan.deinit(allocator);

        for (packages) |package| {
            if (plan.seed) |seed| {
                package.simulation.runSeed(allocator, seed) catch |err| {
                    output_mod.print("The replay of \"{s}\" failed in {s} with {t}.\n", .{ plan_text, package.directory, err });
                    return err;
                };
            }
            if (plan.injections.len == 0) {
                continue;
            }
            const replay_one = package.simulation.replay orelse continue;
            replay_one(allocator, plan_text) catch |err| {
                output_mod.print("The replay of \"{s}\" failed in {s} with {t}.\n", .{ plan_text, package.directory, err });
                return err;
            };
        }
        output_mod.print("The replay of \"{s}\" passed.\n", .{plan_text});
        return;
    }

    // A worker is one round of the run that spawned it: it exercises what it was given and writes
    // what it reached to the handover file, and the run that spawned it reads coverage and prints the
    // report. Nothing here is printed twice, because the worker prints only what happens as it goes.
    if (args.worker) {
        return runWorkerRound(allocator, init, args, packages);
    }

    // Said before any of the work starts, and again at each stage, because all of it takes minutes
    // and the report comes at the end. A run that says nothing until then cannot be told from one
    // that has hung, which is exactly what it looked like on 2026-09-11.
    output_mod.print("\nDeterministic simulation of {d} package{s}. The report comes at the end.\n", .{ packages.len, plural(packages.len) });

    // The wall clock this run reports at the end. Started here rather than at the top of the
    // function so `--replay`, which returns above, never pays for it. Reading a clock needs an
    // `Io`, and `startRun` builds its own for reading sources and drops it, so this is one of its
    // own, used for two timestamps and nothing else.
    // It also spawns kcov, which is looked up on the PATH this process was started with: an `Io`
    // built without the environment gives a spawned process the standard library's own default
    // PATH, which is not where a kcov installed under a home directory sits.
    var timing = std.Io.Threaded.init(allocator, .{ .environ = init.environ });
    defer timing.deinit();
    const timing_io = timing.io();
    const started_at = std.Io.Clock.Timestamp.now(timing_io, .awake);

    // What each function's exercising cost, collected by the parent as the child reports it. Freed
    // here rather than where it is filled, because it is read once the whole run is over.
    defer isolate_mod.freeTimings(allocator);

    var run = try startRun(allocator, init, args, packages);
    defer run.deinit();

    output_mod.print("  Read {d} source file{s}, with {d} function{s} to exercise.\n", .{ run.sources.len, plural(run.sources.len), run.exercised.len, plural(run.exercised.len) });

    // Every annotation the run recorded, from every round or from the one in-process pass. What each
    // simulation file annotated ticks that file's own module and nothing else, so a function is
    // covered only where its own simulation exercised it.
    var annotated: std.ArrayList(Annotated) = .empty;
    defer {
        for (annotated.items) |entry| allocator.free(entry.name);
        annotated.deinit(allocator);
    }

    const under_kcov = runUnderKcov(allocator, timing_io, init, args, &run, &annotated) catch |err| switch (err) {
        error.KcovMissing => false,
        else => return err,
    };

    if (!under_kcov) {
        for (packages) |package| {
            run.faults_injected += try package.simulation.explore(allocator);

            // The names move into `annotated` above, which frees them; the slice they arrived in is
            // this loop's to release either way.
            const package_annotated = try package.simulation.trace(allocator);
            defer allocator.free(package_annotated);
            errdefer {
                for (package_annotated) |entry| allocator.free(entry.name);
            }
            try annotated.appendSlice(allocator, package_annotated);
        }
    }

    output_mod.print("  Reading what those calls reached.\n", .{});
    try checkCoverage(&run, annotated.items);

    // Under kcov the first round swept the seeds, so a failure there has already ended the run.
    if (!under_kcov) {
        try sweepSeeds(allocator, packages);
    }

    const elapsed = started_at.durationTo(std.Io.Clock.Timestamp.now(timing_io, .awake));
    try reportRun(&run, elapsed.raw.nanoseconds, packages);
}

// Every package's seed sweep, with the one command that reproduces a failure printed beside it.
fn sweepSeeds(allocator: std.mem.Allocator, packages: []const Package) !void {
    for (packages) |package| {
        output_mod.print("  {s}: sweeping {d} seed{s}.\n", .{ package.directory, package.simulation.seeds.len, plural(package.simulation.seeds.len) });
        for (package.simulation.seeds) |seed| {
            package.simulation.runSeed(allocator, seed) catch |err| {
                output_mod.print("Seed {d} failed in {s} with {t}.\n", .{ seed, package.directory, err });
                output_mod.print("Reproduce it with: flt --replay \"seed={d}\"\n", .{seed});
                return err;
            };
        }
    }
}

// The rounds under kcov, or `error.KcovMissing` when they cannot happen: kcov is not there to be
// run, or the run was not told where its sources are. Either way one line says so, and the caller
// carries on with coverage from annotations alone. Any other error ends the run. Returns true when
// the rounds ran.
fn runUnderKcov(
    allocator: std.mem.Allocator,
    io: std.Io,
    init: std.process.Init.Minimal,
    args: Args,
    run: *Run,
    annotated: *std.ArrayList(Annotated),
) !bool {
    if (args.sources_root.len == 0) {
        output_mod.print("  The run was not told where its sources are, so coverage comes from annotations alone.\n", .{});
        return error.KcovMissing;
    }

    // Absolute, because kcov reports each file by the path the compiler recorded, which is absolute,
    // and a reported name is matched against the copy's path under this root. The build hands the
    // root over relative to the sandbox the run stands in.
    const sources_root = std.Io.Dir.cwd().realPathFileAlloc(io, args.sources_root, allocator) catch {
        output_mod.print("  The sources root {s} cannot be opened, so coverage comes from annotations alone.\n", .{args.sources_root});
        return error.KcovMissing;
    };
    defer allocator.free(sources_root);

    const worker = std.process.executablePathAlloc(io, allocator) catch {
        output_mod.print("  The run cannot find its own executable, so coverage comes from annotations alone.\n", .{});
        return error.KcovMissing;
    };
    defer allocator.free(worker);

    var worker_args: std.ArrayList([]const u8) = .empty;
    defer worker_args.deinit(allocator);
    try worker_args.appendSlice(allocator, &.{ "--repository", args.repository, "--report", args.report_path });
    if (args.only_file.len != 0) {
        try worker_args.appendSlice(allocator, &.{ "--file", args.only_file });
    }
    if (args.only_function.len != 0) {
        try worker_args.appendSlice(allocator, &.{ "--function", args.only_function });
    }
    if (args.no_color) {
        try worker_args.append(allocator, "--no-color");
    }

    // The environment this process was started with, handed to kcov and through it to the worker,
    // so a bare `kcov` is looked up on the same PATH this process has rather than a built-in one.
    var environ_map = try init.environ.createMap(allocator);
    defer environ_map.deinit();

    var state: RoundState = .{
        .allocator = allocator,
        .run = run,
        .annotated = annotated,
        .sources_root = sources_root,
    };
    var counts: rounds.Counts = .{};
    rounds.runRounds(allocator, io, .{
        .kcov = args.kcov,
        .out_dir = args.kcov_out,
        .sources_root = sources_root,
        .worker = worker,
        .worker_args = worker_args.items,
        .environ_map = &environ_map,
    }, state.subject(), &counts) catch |err| switch (err) {
        error.KcovMissing => {
            output_mod.print("  kcov is not on the PATH, so coverage comes from annotations alone. Install it, or name it with -Dkcov=<path>.\n", .{});
            return error.KcovMissing;
        },
        else => return err,
    };
    run.rounds_run = counts.rounds_run;
    return true;
}

// What the rounds loop reaches back into: the run's checklists, and everything the rounds have
// annotated so far.
const RoundState = struct {
    allocator: std.mem.Allocator,
    run: *Run,
    annotated: *std.ArrayList(Annotated),
    sources_root: []const u8,

    // How many rounds have been absorbed. The first round lists every function, whatever its
    // checklist says, so a round under kcov exercises exactly what an ordinary run does.
    absorbed: usize = 0,

    fn subject(self: *RoundState) rounds.Subject {
        return .{ .ctx = self, .writeRemaining = writeRemaining, .absorb = absorb, .remainingCount = remainingCount };
    }

    fn writeRemaining(ctx: *anyopaque, io: std.Io, path: []const u8) anyerror!usize {
        const self: *RoundState = @ptrCast(@alignCast(ctx));
        var functions: std.ArrayList(handover.Function) = .empty;
        defer functions.deinit(self.allocator);
        for (self.run.exercised, 0..) |spec, index| {
            if (self.absorbed != 0 and self.run.checklists[index].untickedObservableCount() == 0) {
                continue;
            }
            try functions.append(self.allocator, .{ .file = spec.file, .function = spec.function_name, .occurrence = spec.occurrence });
        }
        try handover.writeRemaining(self.allocator, io, path, functions.items);
        return functions.items.len;
    }

    fn absorb(ctx: *anyopaque, io: std.Io, round_dir: []const u8, handover_path: []const u8) anyerror!usize {
        const self: *RoundState = @ptrCast(@alignCast(ctx));
        self.absorbed += 1;

        const cov_path = try std.fmt.allocPrint(self.allocator, "{s}/cov.xml", .{round_dir});
        defer self.allocator.free(cov_path);
        var covered = covered_lines.readCobertura(self.allocator, io, cov_path) catch |err| {
            output_mod.print("kcov wrote no coverage file at {s}, so the round cannot be read.\n", .{cov_path});
            return err;
        };
        defer covered.deinit();

        var ticked = tickChecklistsFromLines(self.run.checklists, self.run.exercised, &covered, self.sources_root);

        var handed = try handover.readHandover(self.allocator, io, handover_path);
        defer handed.deinit();
        for (handed.annotations) |entry| {
            // The module is named the way the run's own sources are, so the source's own name is
            // used rather than a copy: `annotated` frees its names and nothing else, the same as
            // the in-process run, whose modules are the generated root's own literals.
            try self.annotated.append(self.allocator, .{
                .module = moduleNameFrom(self.run.sources, entry.module),
                .name = try self.allocator.dupe(u8, entry.name),
                .from_runner = entry.from_runner,
            });
        }
        for (handed.timings) |entry| {
            try isolate_mod.addTimingFrom(entry.file, entry.function, entry.nanos, entry.calls, self.allocator);
        }
        self.run.faults_injected += handed.counts.faults_injected;
        calls_stepped_over += handed.counts.stepped_over;
        isolate_mod.addStalled(handed.counts.stalled);

        var before: usize = 0;
        for (self.run.checklists) |checklist| {
            before += checklist.tickedCount();
        }
        try tickChecklistsFromTrace(self.allocator, self.run.checklists, self.run.exercised, self.annotated.items);
        var after: usize = 0;
        for (self.run.checklists) |checklist| {
            after += checklist.tickedCount();
        }
        ticked += after - before;
        return ticked;
    }

    fn remainingCount(ctx: *anyopaque) usize {
        const self: *RoundState = @ptrCast(@alignCast(ctx));
        var left: usize = 0;
        for (self.run.checklists) |checklist| {
            if (checklist.untickedObservableCount() != 0) {
                left += 1;
            }
        }
        return left;
    }
};

// The run's own copy of a module name a worker handed over, or an empty name when the worker named
// a module the run did not read, which matches no function and ticks nothing.
pub fn moduleNameFrom(sources: []const SourceFile, module: []const u8) []const u8 {
    for (sources) |source| {
        if (std.mem.eql(u8, source.file, module)) {
            return source.file;
        }
    }
    return "";
}

// One round, run under kcov on behalf of the run that spawned this process. Exercises what it was
// given, sweeps the seeds on the first round, and writes what it reached and what it cost to the
// handover file. A failure ends the process non-zero with the failure printed, exactly as the
// in-process run prints it, and the run that spawned it stops there.
fn runWorkerRound(allocator: std.mem.Allocator, init: std.process.Init.Minimal, args: Args, packages: []const Package) !void {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    round = args.round;

    // The module and the annotation channel share one `Exercised` type with the run, so the listed
    // functions are turned into that and kept for as long as the runner reads them.
    var listed: std.ArrayList(Exercised) = .empty;
    defer listed.deinit(allocator);
    var read_functions: []handover.Function = &.{};
    defer handover.freeRemaining(allocator, read_functions);
    if (args.remaining_path.len != 0) {
        read_functions = try handover.readRemaining(allocator, io, args.remaining_path);
        for (read_functions) |entry| {
            try listed.append(allocator, .{ .file = entry.file, .function_name = entry.function, .occurrence = entry.occurrence });
        }
        remaining = listed.items;
    }

    defer isolate_mod.freeTimings(allocator);

    var run = try startRun(allocator, init, args, packages);
    defer run.deinit();

    var annotated: std.ArrayList(Annotated) = .empty;
    defer {
        for (annotated.items) |entry| allocator.free(entry.name);
        annotated.deinit(allocator);
    }
    for (packages) |package| {
        run.faults_injected += try package.simulation.explore(allocator);
        const package_annotated = try package.simulation.trace(allocator);
        defer allocator.free(package_annotated);
        errdefer {
            for (package_annotated) |entry| allocator.free(entry.name);
        }
        try annotated.appendSlice(allocator, package_annotated);
    }

    if (round == 1) {
        try sweepSeeds(allocator, packages);
    }

    // The timings are keyed the way the child named them, file and function with a tab between.
    var timings: std.ArrayList(handover.Timing) = .empty;
    defer timings.deinit(allocator);
    for (isolate_mod.everyTiming()) |timing| {
        const split = std.mem.indexOfScalar(u8, timing.key, '\t') orelse continue;
        try timings.append(allocator, .{
            .file = timing.key[0..split],
            .function = timing.key[split + 1 ..],
            .nanos = timing.nanos,
            .calls = timing.calls,
        });
    }
    var annotations: std.ArrayList(handover.Annotation) = .empty;
    defer annotations.deinit(allocator);
    for (annotated.items) |entry| {
        try annotations.append(allocator, .{ .module = entry.module, .name = entry.name, .from_runner = entry.from_runner });
    }
    try handover.writeHandover(allocator, io, args.handover_path, annotations.items, timings.items, .{
        .faults_injected = run.faults_injected,
        .stepped_over = calls_stepped_over,
        .stalled = isolate_mod.stalledCount(),
    });
}


// What a package hands the enumeration: the files it owns, the checklists it registered, and which
// file's own declarations are the runner's plumbing rather than ported logic.
// Every one of them is the package's own knowledge, which is why they arrive as values rather than
// being read from anything here.
pub const AccountingOptions = struct {
    source_files: []const SourceFile,
    registered: []const FunctionTally,
};

// One file this package owns whose own declarations `checkEveryDeclarationAccountedFor` walks.
pub const SourceFile = struct {
    file: []const u8,
    source: [:0]const u8,
};
// What `accountFor` decided about one declaration. Carries no payload, so a test can compare a
// result against a plain enum literal (`== .structural`).
pub const Accounting = enum { registered, structural, unaccounted };
// Split out from `checkEveryDeclarationAccountedFor` so the classification itself is provable
// against a small fixture directly (`sim.test.zig`) rather than only by walking the package's own
// real source. Checks `declaration`, found in `file`, against `registered` (has this run given it a
// checklist) and, when `isRunnerFile` says the file is the package's own simulation code, against
// the runner's own plumbing. The
// first is matched by file, name and occurrence
// together, never by name alone, since two declarations sharing a name in one file (`log.zig`'s two
// `dispatch`s, its two `log`s, `random_generator.zig`'s two `random`s) would otherwise let one that
// is genuinely called stand in for one that is not: exactly the ambiguity that made the 28 functions
// this pass registers unable to be told apart from dead code on paper alone. `structural_names` is
// matched by name alone: `sim_structural_declarations` below is the one real caller of this, and none
// of its own names collide with `Environment`'s five method names, which are the only declarations in
// the framework's own files this ever needs to tell apart from runner code.
pub fn accountFor(
    registered: []const FunctionTally,
    file: []const u8,
    declaration: Declaration,
    is_harness: bool,
) Accounting {
    for (registered) |tally| {
        if (tally.occurrence == declaration.occurrence and
            std.mem.eql(u8, tally.file, file) and
            std.mem.eql(u8, tally.function, declaration.name))
        {
            return .registered;
        }
    }

    // Every declaration in the runner's own file is plumbing. The file exists to exercise the
    // simulation and holds no ported logic, so naming its declarations one by one was a list that
    // grew with the runner and told a reader nothing the file's own name does not.
    if (is_harness) {
        return .structural;
    }

    return .unaccounted;
}
// Walks every `fn` declaration `all_source_files` holds and classifies each with `accountFor`,
// printing one line for anything that is not an ordinary registered checklist so a reader can see why
// (`STRUCTURAL` for `sim.zig`'s own runner code) and one for anything
// `accountFor` could not account for at all, which is what fails the build. Returns whether every
// declaration was accounted for.
pub fn checkEveryDeclarationAccountedFor(
    allocator: std.mem.Allocator,
    options: AccountingOptions,
    report: *std.Io.Writer.Allocating,
) !bool {
    const registered = options.registered;
    var all_accounted = true;

    for (options.source_files) |source_file| {
        const declarations = try listDeclarations(allocator, source_file.source);
        defer freeDeclarations(allocator, declarations);

        for (declarations) |declaration| {
            switch (accountFor(registered, source_file.file, declaration, isHarness(source_file.source))) {
                .registered => {},
                .structural => {
                    try report.writer.print(
                        "STRUCTURAL {s}:{d} \"{s}\": harness code exercising the run, so nothing fault tests it.\n",
                        .{ source_file.file, declaration.line, declaration.name },
                    );
                },
                .unaccounted => {
                    try report.writer.print(
                        "UNACCOUNTED {s}:{d} \"{s}\" has no coverage checklist.\n",
                        .{ source_file.file, declaration.line, declaration.name },
                    );
                    all_accounted = false;
                },
            }
        }
    }

    return all_accounted;
}
// Runs every seed-chosen scenario for one seed, in a fixed order so the same seed does the same
// work every time it is run: reproducibility depends on the sequence of operations being fixed,
// not only on the seed each one starts from. `allocator_fail_indices` is how many allocation
// ordinals this seed's allocator scenario tries.
// What this run exercised, function by function, so the summary can say which functions were tested,
// how many of each one's paths ran, and how many faults went into each. The counters live here
// rather than in `testing/sim` because which function a scenario is exercising is this package's
// own knowledge: the framework only ever sees a subject and a point.
// `pub` only so `accountFor's own fixture test (`sim.test.zig`) can construct one directly;
// nothing outside this file's own tests does.
pub const FunctionTally = struct {
    file: []const u8,
    function: []const u8,

    // Which same-named declaration in `file` this is: zero unless `function` is one of the three
    // names (`log.zig`'s `dispatch` and `log`, `random_generator.zig`'s `random`) this package
    // declares twice, in different containers. What `checkEveryDeclarationAccountedFor` matches an
    // enumerated declaration against, so the two same-named declarations are never conflated into
    // one accounting slot.
    occurrence: usize = 0,

    // Ticked, the total that can be ticked, and the paths no annotation can reach (a short-circuit
    // or a `try`, which have no statement position), from a coverage checklist. `null` for a
    // function this package exercises without a dedicated one of its own; every function this file
    // exercises has one today. `total` counts only what a run can tick, so a function reads as passing
    // when it has reached everything reachable, and the unobservable count is printed beside it
    // rather than folded in, where it would make a covered function look uncovered forever.
    paths: ?struct { ticked: usize, total: usize, unobservable: usize = 0 } = null,
};

// The colour codes and marks a report is written with. Its own file so anything that prints can
// reach it without reaching the whole framework.
pub const Style = style_mod.Style;

// Reads every Zig file under one directory, from the directory itself rather than a list somebody
// keeps by hand: a file added to a package is in the walk the moment it exists, and one deleted
// stops being walked without anybody remembering to remove a line.
//
// Read at run time rather than embedded at compile time for the same reason: `@embedFile` needs a
// name per file, which is the hand-kept list this replaces. Paths are relative to the repository
// root, which is where a run starts, the same assumption the coverage report written to `tmp/`
// already makes.
// `open_at` is where the directory is on disk and `directory` is what the files in it are named
// after. They are the same thing for a caller standing in the repository, and different for a run,
// which stands in a sandbox and reads the repository by its own path. Keeping them apart is what
// stops the sandbox's path leaking into every name in the report.
pub fn readSources(
    allocator: std.mem.Allocator,
    io: std.Io,
    open_at: []const u8,
    directory: []const u8,
    excluded_directories: []const []const u8,
) ![]SourceFile {
    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }

    try collectSourcePaths(allocator, io, open_at, "", excluded_directories, &names);

    // Sorted so a run reports the same files in the same order on every machine: a directory walk
    // has no order of its own, and hash-map-shaped output is the nondeterminism this whole
    // mechanism exists to keep out.
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var sources = try allocator.alloc(SourceFile, names.items.len);
    var written: usize = 0;
    errdefer {
        for (sources[0..written]) |source| {
            allocator.free(source.file);
            allocator.free(source.source);
        }
        allocator.free(sources);
    }

    for (names.items) |name| {
        // A package whose directory is the repository root is named ".", and a file in it is named
        // by itself: "./thing.zig" and "thing.zig" are the same file, and the generated root says
        // the second, so a run that said the first would pair nothing with anything.
        const path = if (std.mem.eql(u8, directory, "."))
            try allocator.dupe(u8, name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory, name });
        errdefer allocator.free(path);

        // Read from where the package actually is, which is not where it is named from: the run
        // stands in a sandbox rather than in the repository, so the two are only the same when a
        // caller passes the same thing for both.
        const reading = if (std.mem.eql(u8, open_at, directory))
            try allocator.dupe(u8, path)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ open_at, name });
        defer allocator.free(reading);

        const text = try std.Io.Dir.cwd().readFileAllocOptions(io, reading, allocator, .unlimited, .of(u8), 0);
        sources[written] = .{ .file = path, .source = text };
        written += 1;
    }

    return sources;
}

// Every Zig file under `directory`, including the ones in directories below it, named relative to
// `directory` with `prefix` already carrying however far down the walk is. Recursive so a package
// that groups its code into subdirectories is fault tested without anything being told about them.
//
// A `.test.zig` file and a `fuzz_` entry point are skipped: neither holds ported-package logic for
// a checklist to be built from. Simulation code is not skipped here, since what makes a file
// simulation code is what it imports rather than where it sits: `isHarness` decides that when the
// functions are listed.
// Whether `name` is one of the directory names the build said to leave out.
fn isExcluded(excluded_directories: []const []const u8, name: []const u8) bool {
    for (excluded_directories) |excluded| {
        if (std.mem.eql(u8, excluded, name)) {
            return true;
        }
    }
    return false;
}

fn collectSourcePaths(
    allocator: std.mem.Allocator,
    io: std.Io,
    directory: []const u8,
    prefix: []const u8,
    excluded_directories: []const []const u8,
    names: *std.ArrayList([]const u8),
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true });
    defer dir.close(io);

    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                // A dot-directory is never a package's own code: it is a cache, a checkout's own
                // state, or the framework this run was compiled from, and reading the last of
                // those would fault test the tool against the repository it is fault testing.
                if (std.mem.startsWith(u8, entry.name, ".")) {
                    continue;
                }

                // A directory the build was told to leave out. Named rather than matched, so a
                // project says which of its directories hold what exercises the code rather than what
                // is exercised.
                if (isExcluded(excluded_directories, entry.name)) {
                    continue;
                }
                const below = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory, entry.name });
                defer allocator.free(below);
                const below_prefix = try std.fmt.allocPrint(allocator, "{s}{s}/", .{ prefix, entry.name });
                defer allocator.free(below_prefix);
                try collectSourcePaths(allocator, io, below, below_prefix, excluded_directories, names);
            },
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".zig")) {
                    continue;
                }
                if (std.mem.endsWith(u8, entry.name, ".test.zig")) {
                    continue;
                }
                if (std.mem.startsWith(u8, entry.name, "fuzz_")) {
                    continue;
                }
                // A build script and its manifest are how a repository is built rather than code
                // somebody wrote to be exercised, and nothing generates a checklist for them, so
                // reading them here would report every function in them as unaccounted for.
                if (std.mem.eql(u8, entry.name, "build.zig") or std.mem.eql(u8, entry.name, "build.zig.zon")) {
                    continue;
                }
                // A repository can hold a file named `.zig` that is not Zig: a generated record, a
                // template, something a tool left behind. Nothing can be fault tested in one, and
                // trying ends the whole run rather than that one file.
                if (!parsesAsZig(allocator, io, directory, entry.name)) {
                    continue;
                }
                try names.append(allocator, try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, entry.name }));
            },
            else => {},
        }
    }
}

// Whether a file is valid Zig with a declaration at its top level.
fn parsesAsZig(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, name: []const u8) bool {
    const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory, name }) catch return false;
    defer allocator.free(path);

    const source = std.Io.Dir.cwd().readFileAllocOptions(io, path, allocator, .unlimited, .of(u8), 0) catch return false;
    defer allocator.free(source);

    var tree = std.zig.Ast.parse(allocator, source, .zig) catch return false;
    defer tree.deinit(allocator);
    return tree.errors.len == 0;
}

// Every source of every package the build found, in one list sorted by path, so the run fault tesures
// the whole repository at once and reports it in an order that does not depend on which package
// the build happened to list first.
pub fn readEverySource(allocator: std.mem.Allocator, io: std.Io, repository: []const u8, packages: []const Package) ![]SourceFile {
    var collected: std.ArrayList(SourceFile) = .empty;
    errdefer {
        for (collected.items) |source| {
            allocator.free(source.file);
            allocator.free(source.source);
        }
        collected.deinit(allocator);
    }

    for (packages) |package| {
        // The package's own directory, spelled the way the build found it, resolved against the
        // repository. The names the report goes on to use come from the walk below this, so they
        // stay relative to the package and never carry the repository's own path.
        const where = if (std.mem.eql(u8, package.directory, "."))
            try allocator.dupe(u8, repository)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ repository, package.directory });
        defer allocator.free(where);

        const package_sources = try readSources(allocator, io, where, package.directory, package.excluded_directories);
        // The files themselves move into `collected`, which owns them from here; the slice they
        // arrived in is this loop's to release either way.
        defer allocator.free(package_sources);
        errdefer {
            for (package_sources) |source| {
                allocator.free(source.file);
                allocator.free(source.source);
            }
        }
        // A package whose directory holds another package's reads that one's files too, because the
        // walk below a directory goes all the way down. A file belongs to one package, so the
        // second reading of it is dropped: kept, every function under a nested source directory got
        // two checklists, and a repository laid out as `src`, `src/cmd` and `src/lib` reported
        // twice the files, functions, calls and paths it has.
        for (package_sources) |source| {
            if (alreadyRead(collected.items, source.file)) {
                allocator.free(source.file);
                allocator.free(source.source);
                continue;
            }
            try collected.append(allocator, source);
        }
    }

    std.mem.sort(SourceFile, collected.items, {}, struct {
        fn lessThan(_: void, a: SourceFile, b: SourceFile) bool {
            return std.mem.lessThan(u8, a.file, b.file);
        }
    }.lessThan);

    return collected.toOwnedSlice(allocator);
}

// Whether one of these files has been read already. Linear, because the list is one entry per
// `.zig` file in a repository and is built once per run.
fn alreadyRead(sources: []const SourceFile, file: []const u8) bool {
    for (sources) |source| {
        if (std.mem.eql(u8, source.file, file)) {
            return true;
        }
    }
    return false;
}

pub fn freeSources(allocator: std.mem.Allocator, sources: []SourceFile) void {
    for (sources) |source| {
        allocator.free(source.file);
        allocator.free(source.source);
    }
    allocator.free(sources);
}

// The text of one file the walk read, by the path the exercised table names it under.
pub fn sourceFor(sources: []const SourceFile, file: []const u8) [:0]const u8 {
    for (sources) |source| {
        if (std.mem.eql(u8, source.file, file)) {
            return source.source;
        }
    }
    std.debug.panic("{s} is not one of the files read for this run.", .{file});
}

// Which of a package's own functions a scenario can reach, worked out from the code rather than
// from anything written down: start at the scenario, take every call its body makes, and follow
// each one that lands on a declaration in these sources, repeating until nothing new is reached.
//
// A scenario reaches most of what it exercises indirectly, through a helper, through a struct's own
// method, or through a comptime-duck-typed operation, so the calls one body makes are not enough on
// their own. The transitive closure is.
//
// A call through a function pointer or a field is not followed, since nothing in the source says
// where it lands. What that misses stays unaccounted, and the enumeration says so rather than this
// pretending to know.
pub const Reached = struct {
    file: []const u8,
    name: []const u8,
    occurrence: usize,
};

// The names in what this returns are owned by the caller, freed with `freeReached`.
pub fn freeReached(allocator: std.mem.Allocator, reached: []const Reached) void {
    for (reached) |entry| {
        allocator.free(entry.name);
    }
    allocator.free(reached);
}

pub fn reachableFrom(
    max_depth: usize,
    allocator: std.mem.Allocator,
    sources: []const SourceFile,
    start_file: []const u8,
    start_name: []const u8,
    start_occurrence: usize,
) ![]Reached {
    var seen: std.ArrayList(Reached) = .empty;
    errdefer seen.deinit(allocator);

    var queue: std.ArrayList(Reached) = .empty;
    defer {
        // Whatever is still queued when the walk stops was duped here and never handed over.
        for (queue.items) |entry| {
            if (!containsReached(seen.items, entry)) {
                allocator.free(entry.name);
            }
        }
        queue.deinit(allocator);
    }
    // The starting point is the caller's own memory, so it is never freed here.
    try queue.append(allocator, .{ .file = start_file, .name = try allocator.dupe(u8, start_name), .occurrence = start_occurrence });
    const start_copy = queue.items[0].name;
    defer allocator.free(start_copy);

    var depth: usize = 0;
    while (queue.items.len != 0 and depth < max_depth) : (depth += 1) {
        const current = queue.pop().?;

        const source = sourceForOrNull(sources, current.file) orelse continue;
        const calls = listCalls(allocator, source, current.name, current.occurrence) catch continue;
        defer freeCalls(allocator, calls);

        for (calls) |call| {
            var found: ?Reached = null;
            for (sources) |candidate| {
                const declarations = listDeclarations(allocator, candidate.source) catch continue;
                defer freeDeclarations(allocator, declarations);
                var matches: usize = 0;
                var occurrence: usize = 0;
                for (declarations) |declaration| {
                    if (std.mem.eql(u8, declaration.name, call.name)) {
                        matches += 1;
                        occurrence = declaration.occurrence;
                    }
                }
                // A name declared twice in one file cannot be told apart from a call, and a name
                // declared in two files is the same problem across files: both are left alone.
                if (matches == 1) {
                    if (found != null) {
                        found = null;
                        break;
                    }
                    found = .{ .file = candidate.file, .name = try allocator.dupe(u8, call.name), .occurrence = occurrence };
                }
            }

            const target = found orelse continue;
            if (containsReached(seen.items, target) or containsReached(queue.items, target)) {
                // Already known, so the copy taken for it is not needed.
                allocator.free(target.name);
                continue;
            }
            try seen.append(allocator, target);
            try queue.append(allocator, target);
        }
    }

    return seen.toOwnedSlice(allocator);
}

fn containsReached(list: []const Reached, target: Reached) bool {
    for (list) |entry| {
        if (entry.occurrence == target.occurrence and
            std.mem.eql(u8, entry.file, target.file) and
            std.mem.eql(u8, entry.name, target.name))
        {
            return true;
        }
    }
    return false;
}

fn sourceForOrNull(sources: []const SourceFile, file: []const u8) ?[:0]const u8 {
    for (sources) |source| {
        if (std.mem.eql(u8, source.file, file)) {
            return source.source;
        }
    }
    return null;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("sim.test.zig");
}
