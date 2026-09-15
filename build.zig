const std = @import("std");
const discover = @import("src/cmd/discover.zig");

// Faultline's build. It produces two modules and one executable.
//
// The modules are what a repository being measured compiles against: `sim`, the framework that
// drives every function and injects every fault, and `log`, the channel a function sends its
// annotations down. The executable is `flt`, which finds what to measure, generates the root file,
// compiles the simulation binary and runs it.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    // Always on in this repository's own build. The only build of `log.zig` whose value
    // matters is the one the command generates for the repository it is measuring, and that one is
    // always on because a run without the trace points measures nothing. Leaving this off here
    // would compile the tool's own tests for the annotation channel down to nothing and pass them
    // by testing an empty function.
    options.addOption(bool, "annotations_enabled", true);
    // Where a run writes the full checklist. The command overrides this when it generates the
    // options module for the repository it is measuring; this value is what the tool's own tests
    // and anything building the module directly get.
    options.addOption([]const u8, "report_path", "tmp/sim-coverage-report.txt");
    // Where the framework source a run is compiled against lives, fixed when this binary was built.
    //
    // The contract says nothing is located relative to the binary, so this is not worked out from
    // where the executable sits: copy it, move it or symlink it and a run still compiles against
    // the source this build was made from. `-Dsource=<path>` names somewhere else, for an install
    // that ships the source separately from the checkout it was built in.
    options.addOption(
        []const u8,
        "source_root",
        b.option([]const u8, "source", "Where the framework source a run compiles against lives") orelse
            b.build_root.path.?,
    );
    const options_module = options.createModule();

    // The minimal package a repository being measured depends on: a log to take as a parameter, a
    // compile-time flag, and one function to mark a branch with. Nothing else.
    const log_module = b.addModule("log", .{
        .root_source_file = b.path("src/log/log.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "flt_options", .module = options_module },
        },
    });

    // The framework. What a repository imports as `sim`, not as `faultline`: `src/sim.zig` decides
    // whether a file is harness code by looking for the literal text `@import("sim")` in it, so the
    // name is part of how a run reads a tree rather than a label that can be chosen freely.
    const sim_module = b.addModule("sim", .{
        .root_source_file = b.path("src/framework/sim.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            // The framework reads back what the channel recorded, so both ends have to agree on
            // one `Log` type rather than each declaring its own.
            .{ .name = "log", .module = log_module },
        },
    });

    // Discovery: the walk `addFaultTest` runs and the root it builds from what that found. A module
    // of its own so its tests run with the rest, and imported by `build.zig` directly rather than
    // compiled into anything shipped.
    const flt_module = b.createModule(.{
        .root_source_file = b.path("src/cmd/discover.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sim", .module = sim_module },
            .{ .name = "log", .module = log_module },
            .{ .name = "flt_options", .module = options_module },
        },
    });

    // The tests. Each source file names its own test file in a `test` block at its foot, so a
    // module's tests are collected by building that module: `sim` reaches everything the framework
    // is made of, `log` reaches the annotation channel, and the command's own module reaches
    // discovery.
    const sim_tests = b.addTest(.{ .root_module = sim_module });
    const run_sim_tests = b.addRunArtifact(sim_tests);

    const log_tests = b.addTest(.{ .root_module = log_module });
    const run_log_tests = b.addRunArtifact(log_tests);

    const flt_tests = b.addTest(.{ .root_module = flt_module });
    const run_flt_tests = b.addRunArtifact(flt_tests);
    // The tool's tests read this repository's own tree, so they run from its root rather than from
    // wherever the test binary happens to be written.
    run_flt_tests.setCwd(b.path("."));

    // `ReleaseSafe` as well as the default, because the simulation binary a run compiles is built
    // `ReleaseSafe`, and a check that only ever runs in `Debug` has not checked the build that
    // actually drives anybody's code.
    const release_sim_module = b.createModule(.{
        .root_source_file = b.path("src/framework/sim.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .imports = &.{
            .{ .name = "log", .module = log_module },
        },
    });
    const release_sim_tests = b.addTest(.{ .root_module = release_sim_module });
    const run_release_sim_tests = b.addRunArtifact(release_sim_tests);

    // What the whole run took, reported at the end. A build step has no clock of its own, so the
    // start is stamped into a file by a step every test run waits on, and read back by a step that
    // waits on every test run.
    const started_at = b.addSystemCommand(&.{ "sh", "-c", "mkdir -p tmp && date +%s > tmp/unit-tests-started" });
    started_at.has_side_effects = true;
    for ([_]*std.Build.Step.Run{ run_sim_tests, run_log_tests, run_flt_tests, run_release_sim_tests }) |run| {
        run.step.dependOn(&started_at.step);
    }

    const report_elapsed = b.addSystemCommand(&.{
        "sh",
        "-c",
        "took=$(( $(date +%s) - $(cat tmp/unit-tests-started) )); " ++
            "if [ \"$took\" -ge 60 ]; then printf 'Ran every unit test in %dm %02ds.\\n' $((took / 60)) $((took % 60)); " ++
            "else printf 'Ran every unit test in %ds.\\n' \"$took\"; fi",
    });
    report_elapsed.has_side_effects = true;
    for ([_]*std.Build.Step.Run{ run_sim_tests, run_log_tests, run_flt_tests, run_release_sim_tests }) |run| {
        report_elapsed.step.dependOn(&run.step);
    }

    const test_step = b.step("test", "Run every unit test, in the default optimisation and again in ReleaseSafe");
    test_step.dependOn(&run_sim_tests.step);
    test_step.dependOn(&run_log_tests.step);
    test_step.dependOn(&run_flt_tests.step);
    test_step.dependOn(&run_release_sim_tests.step);
    test_step.dependOn(&report_elapsed.step);

    // Each command captures its own what-changed baseline when it passes, so running one by hand
    // marks that target up to date exactly as a full run does, and a target already proved is not
    // run again on the next commit. The capture depends on everything the step depends on, so a
    // failure never reaches it.
    // What "compiling" means now that Faultline ships no binary: the two modules a project
    // compiles against, built for this host so a break in either is caught here.
    const compiles = b.addTest(.{ .root_module = flt_module });
    b.getInstallStep().dependOn(&captureBaseline(b, "compile", &compiles.step).step);
    test_step.dependOn(&captureBaseline(b, "test", &run_release_sim_tests.step).step);
}

// A step running `what-changed baseline capture <target>` once everything before it has succeeded.
//
// A what-changed that is not installed is not a build failure: a fresh clone can compile before its
// toolchain is complete, so the step reports that it was skipped and leaves the exit status alone.
// That is why it runs through a shell rather than being an ordinary run artifact.
fn captureBaseline(b: *std.Build, target_name: []const u8, after: *std.Build.Step) *std.Build.Step.Run {
    const capture = b.addSystemCommand(&.{
        "sh",
        "-c",
        b.fmt(
            // what-changed's output is collected and echoed rather than left to go straight out,
            // because it seeks to the start of whatever it was handed and writes there, which
            // overwrites the first lines of the build's own output when that is a file.
            "if command -v what-changed >/dev/null 2>&1; then captured=$(what-changed baseline capture {s} 2>&1); echo \"$captured\"; " ++
                "else echo \"what-changed is not installed, so the {s} baseline was not captured.\"; fi",
            .{ target_name, target_name },
        ),
    });
    capture.step.dependOn(after);
    // Without this the step is cached on its arguments and never runs a second time, which would
    // capture the baseline once and leave it stale for every build after.
    capture.has_side_effects = true;
    return capture;
}

// What a project passes to `addFaultTest`.
pub const FaultTestOptions = struct {
    // The modules the code under test imports, exactly as the project's own build declares them.
    // The run compiles against these, so a project never names a dependency twice.
    imports: []const std.Build.Module.Import = &.{},

    // The directories holding the code to fault test. Null lets the walk decide, which is what a
    // project laid out in the ordinary way wants.
    source: ?[]const []const u8 = null,

    // Directory names to leave out of the walk. A project's benchmarks and its test harnesses are
    // code, so the walk takes them for source and asks for every one of their paths to be covered.
    // A harness drives the code rather than being the code driven, and nothing in a tree says which
    // is which, so name them here.
    exclude: []const []const u8 = &.{},

    // The name the project's own code reads its build options from, when that is not `flt_options`.
    options_module: ?[]const u8 = null,

    // What the simulation is built for and at. `ReleaseSafe` because the run's own bounds were
    // measured against it, and a `Debug` build of the same work takes long enough to change what
    // somebody does with the tool.
    target: ?std.Build.ResolvedTarget = null,
    optimize: std.builtin.OptimizeMode = .ReleaseSafe,
};

// Adds the `flt` step to a project's own build: the walk, the wiring, the compile and the run.
//
// Everything happens inside the project's build, so there is no program to install and no second
// compiler invocation. What the run needs is taken from `options.imports`, which is what the
// project's own build already says its modules are.
pub fn addFaultTest(b: *std.Build, options: FaultTestOptions) void {
    const faultline = b.dependency("faultline", .{});
    const target = options.target orelse b.graph.host;

    var threaded = std.Io.Threaded.init(b.allocator, .{});
    const io = threaded.io();

    const project_root = b.build_root.path orelse ".";
    const project = std.Io.Dir.cwd().openDir(io, project_root, .{ .iterate = true }) catch @panic("flt: the project root cannot be opened");

    var layout = discover.Layout{ .excluded_directories = options.exclude };
    if (options.source) |named| {
        layout.source_directories = named;
    } else {
        const by_default = discover.collect(b.allocator, io, project, layout, .source) catch @panic("flt: the tree cannot be walked");
        if (by_default.len == 0) {
            layout.source_directories = discover.detectSourceDirectories(b.allocator, io, project, layout) catch
                @panic("flt: the source directories cannot be worked out");
        }
    }

    // Every `.zig` under a source directory, copied into a directory of the build's own so the
    // generated root can import them by the paths the project spells. A Zig file can only import
    // what is under its own directory, and the generated root may not be written into the project.
    //
    // The directories come from the walk rather than from `layout.source_directories`, which stays
    // null for a project laid out the ordinary way. Reading the field instead copied nothing at all
    // for exactly those projects, and every import in the generated root came back FileNotFound.
    const written = b.addWriteFiles();
    const found = discover.collect(b.allocator, io, project, layout, .source) catch @panic("flt: the tree cannot be walked");
    var copied: std.ArrayList([]const u8) = .empty;
    for (found) |file| {
        var already = false;
        for (copied.items) |seen| {
            if (std.mem.eql(u8, seen, file.directory)) {
                already = true;
            }
        }
        if (already) {
            continue;
        }
        copied.append(b.allocator, file.directory) catch @panic("OOM");
        copyZigFiles(b, written, io, project, file.directory);
    }

    // Said before the compile, because the walk has already decided what will be driven and a
    // reader watching a build wants to know which tree it is looking at.
    std.debug.print("Fault testing the Zig source in {s}.\n", .{std.fs.path.basename(project_root)});

    const text = discover.generateRoot(b.allocator, io, project, layout) catch @panic("flt: the root cannot be generated");
    const root = written.add(discover.generated_root_name, text);

    // Always on: the trace points are what tick a path off a checklist, so a run without them
    // fault tests nothing.
    const run_options = b.addOptions();
    run_options.addOption(bool, "annotations_enabled", true);
    const run_options_module = run_options.createModule();

    var imports: std.ArrayList(std.Build.Module.Import) = .empty;
    imports.appendSlice(b.allocator, options.imports) catch @panic("OOM");
    imports.append(b.allocator, .{ .name = "sim", .module = faultline.module("sim") }) catch @panic("OOM");
    imports.append(b.allocator, .{ .name = "log", .module = faultline.module("log") }) catch @panic("OOM");
    imports.append(b.allocator, .{ .name = "flt_options", .module = run_options_module }) catch @panic("OOM");
    if (options.options_module) |named| {
        imports.append(b.allocator, .{ .name = named, .module = run_options_module }) catch @panic("OOM");
    }

    const simulation = b.addExecutable(.{
        .name = "flt-sim",
        .root_module = b.createModule(.{
            .root_source_file = root,
            .target = target,
            .optimize = options.optimize,
            .imports = imports.items,
        }),
    });

    // The run stands in a directory of its own, never in the project, because the functions it
    // drives are the project's own and a project's own code creates files where it is standing.
    const sandbox = b.cache_root.join(b.allocator, &.{"flt-sandbox"}) catch @panic("OOM");
    std.Io.Dir.cwd().createDirPath(io, sandbox) catch @panic("flt: the sandbox cannot be made");

    const run = b.addRunArtifact(simulation);
    run.setCwd(.{ .cwd_relative = sandbox });
    run.has_side_effects = true;
    run.addArgs(&.{ "--repository", project_root });
    // Absolute, because the run stands in the sandbox rather than in the project, and a relative
    // path would put the report under the sandbox instead of in the build's own cache.
    const report = b.pathJoin(&.{ project_root, b.cache_root.join(b.allocator, &.{"sim-coverage-report.txt"}) catch @panic("OOM") });
    run.addArgs(&.{ "--report", report });
    if (b.option([]const u8, "file", "Fault test only this file")) |only| {
        run.addArgs(&.{ "--file", only });
    }
    if (b.option([]const u8, "function", "Fault test only functions of this name")) |only| {
        run.addArgs(&.{ "--function", only });
    }
    if (b.option([]const u8, "replay", "Reproduce one failure a run already reported")) |plan| {
        run.addArgs(&.{ "--replay", plan });
    }

    b.step("flt", "Fault test every function down every code path").dependOn(&run.step);
}

// Copies every `.zig` file under one source directory into the generated root's directory, keeping
// the path the project spells so the report names files the way the project does.
//
// Dot-directories are skipped, which is what keeps a build cache out of what is copied.
fn copyZigFiles(
    b: *std.Build,
    written: *std.Build.Step.WriteFile,
    io: std.Io,
    project: std.Io.Dir,
    directory: []const u8,
) void {
    const path = if (directory.len == 0) "." else directory;
    var dir = project.openDir(io, path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var entries = dir.iterate();
    while (entries.next(io) catch return) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) {
            continue;
        }
        const below = if (directory.len == 0)
            b.allocator.dupe(u8, entry.name) catch @panic("OOM")
        else
            std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ directory, entry.name }) catch @panic("OOM");

        switch (entry.kind) {
            .directory => copyZigFiles(b, written, io, project, below),
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".zig")) {
                    continue;
                }
                _ = written.addCopyFile(b.path(below), below);
            },
            else => {},
        }
    }
}
