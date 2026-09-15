// Tests for the walk that finds what to fault test and the generator that writes the root file.
//
// Every one of them builds its own fixture tree under `tmp/`, so what is being read is written by
// the test rather than being whatever this repository happens to hold on the day.

const std = @import("std");
const discover = @import("discover.zig");

// One fixture tree, created under `tmp/` and removed when the test ends. Under `tmp/` because that
// is gitignored here, and named for the test so two running at once never share a directory.
const Tree = struct {
    path: []const u8,
    dir: std.Io.Dir,
    io: std.Io,
    threaded: *std.Io.Threaded,
    allocator: std.mem.Allocator,

    fn create(allocator: std.mem.Allocator, name: []const u8) !Tree {
        const threaded = try allocator.create(std.Io.Threaded);
        threaded.* = std.Io.Threaded.init(allocator, .{});
        const io = threaded.io();

        const path = try std.fmt.allocPrint(allocator, "tmp/discover-fixtures/{s}", .{name});
        std.Io.Dir.cwd().deleteTree(io, path) catch {};
        try std.Io.Dir.cwd().createDirPath(io, path);
        const dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });

        return .{ .path = path, .dir = dir, .io = io, .threaded = threaded, .allocator = allocator };
    }

    fn write(self: *Tree, relative: []const u8, text: []const u8) !void {
        if (std.fs.path.dirname(relative)) |parent| {
            try self.dir.createDirPath(self.io, parent);
        }
        try self.dir.writeFile(self.io, .{ .sub_path = relative, .data = text });
    }

    fn makeDirectory(self: *Tree, relative: []const u8) !void {
        try self.dir.createDirPath(self.io, relative);
    }

    fn read(self: *Tree, relative: []const u8) ![]u8 {
        return self.dir.readFileAlloc(self.io, relative, self.allocator, .unlimited);
    }

    fn destroy(self: *Tree) void {
        self.dir.close(self.io);
        std.Io.Dir.cwd().deleteTree(self.io, self.path) catch {};
        self.allocator.free(self.path);
        self.threaded.deinit();
        self.allocator.destroy(self.threaded);
    }
};

test "wanted takes a source module, and leaves a test, a simulation and a fuzz entry point alone" {
    const layout = discover.Layout{};
    try std.testing.expect(discover.wanted(layout, .source, "packages/text/src", "format.zig"));
    try std.testing.expect(!discover.wanted(layout, .source, "packages/text/src", "format.test.zig"));
    try std.testing.expect(!discover.wanted(layout, .source, "packages/text/src", "format.sim.zig"));
    try std.testing.expect(!discover.wanted(layout, .source, "packages/text/src", "fuzz_format.zig"));
    try std.testing.expect(!discover.wanted(layout, .source, "packages/text/src", "notes.md"));
}

test "wanted takes a source module only under the source prefix and suffix" {
    const layout = discover.Layout{};
    try std.testing.expect(!discover.wanted(layout, .source, "apps/cli", "main.zig"));
    try std.testing.expect(!discover.wanted(layout, .source, "packages/text/test", "main.zig"));
}

test "wanted leaves a build script and the generated root out of what is fault tested" {
    const layout = discover.Layout{ .source_directories = &.{""} };
    try std.testing.expect(!discover.wanted(layout, .source, "", "build.zig"));
    try std.testing.expect(!discover.wanted(layout, .source, "", "build.zig.zon"));
    try std.testing.expect(!discover.wanted(layout, .source, "", discover.generated_root_name));
    try std.testing.expect(discover.wanted(layout, .source, "", "main.zig"));
}

test "wanted takes a simulation file under a source directory and leaves one outside it" {
    // A `.sim.zig` outside the source directories was once compiled into the run wherever it sat.
    // One in a documentation directory, beside a scratch file that no longer existed, stopped a
    // whole repository being fault tested with a compiler error about a file nobody had asked for.
    const layout = discover.Layout{ .source_directories = &.{"apps/cli"} };
    try std.testing.expect(discover.wanted(layout, .simulation, "apps/cli", "main.sim.zig"));
    try std.testing.expect(!discover.wanted(layout, .simulation, "apps/cli", "main.zig"));
    try std.testing.expect(!discover.wanted(layout, .simulation, "docs/notes", "scratch.sim.zig"));
}

test "wanted takes a helper, which is a test file that is not a simulation's own" {
    const layout = discover.Layout{};
    try std.testing.expect(discover.wanted(layout, .helper, "packages/text/src", "format.test.zig"));
    try std.testing.expect(!discover.wanted(layout, .helper, "packages/text/src", "format.sim.test.zig"));
    try std.testing.expect(!discover.wanted(layout, .helper, "apps/cli", "main.test.zig"));
}

test "wanted answers differently under a layout that is not the default" {
    const layout = discover.Layout{ .source_prefix = "lib/", .source_suffix = "/code" };
    try std.testing.expect(discover.wanted(layout, .source, "lib/thing/code", "thing.zig"));
    try std.testing.expect(!discover.wanted(layout, .source, "packages/text/src", "format.zig"));
}

test "wanted answers from named directories when the layout has them" {
    const layout = discover.Layout{ .source_directories = &.{"source"} };
    try std.testing.expect(discover.wanted(layout, .source, "source", "thing.zig"));
    try std.testing.expect(discover.wanted(layout, .source, "source/deeper", "thing.zig"));
    try std.testing.expect(!discover.wanted(layout, .source, "elsewhere", "thing.zig"));
}

test "isUnderOneOf matches a directory itself, one below it, and nothing beside it" {
    try std.testing.expect(discover.isUnderOneOf(&.{"src"}, "src"));
    try std.testing.expect(discover.isUnderOneOf(&.{"src"}, "src/deeper"));
    try std.testing.expect(!discover.isUnderOneOf(&.{"src"}, "srcs"));
    try std.testing.expect(!discover.isUnderOneOf(&.{"src"}, "other"));
    try std.testing.expect(discover.isUnderOneOf(&.{""}, "anything/at/all"));
    try std.testing.expect(!discover.isUnderOneOf(&.{}, "src"));
}

test "ignoredDirectoryNames takes the plain names out of a gitignore and leaves the patterns" {
    var tree = try Tree.create(std.testing.allocator, "ignored-names");
    defer tree.destroy();

    try tree.write(".gitignore",
        \\# a comment
        \\
        \\node_modules
        \\/tmp/
        \\zig-out/
        \\*.tsbuildinfo
        \\docs/generated
        \\
    );

    const names = try discover.ignoredDirectoryNames(std.testing.allocator, tree.io, tree.dir);
    defer discover.freeNames(std.testing.allocator, names);

    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("node_modules", names[0]);
    try std.testing.expectEqualStrings("tmp", names[1]);
    try std.testing.expectEqualStrings("zig-out", names[2]);
}

test "ignoredDirectoryNames comes back empty when there is no gitignore" {
    var tree = try Tree.create(std.testing.allocator, "no-gitignore");
    defer tree.destroy();

    const names = try discover.ignoredDirectoryNames(std.testing.allocator, tree.io, tree.dir);
    defer discover.freeNames(std.testing.allocator, names);
    try std.testing.expectEqual(@as(usize, 0), names.len);
}

test "isIgnored finds a name that is there and not one that is not" {
    try std.testing.expect(discover.isIgnored(&.{ "tmp", "zig-out" }, "tmp"));
    try std.testing.expect(!discover.isIgnored(&.{ "tmp", "zig-out" }, "packages"));
    try std.testing.expect(!discover.isIgnored(&.{}, "tmp"));
}

test "isWorktreeRoot is true only where .git is a file" {
    var tree = try Tree.create(std.testing.allocator, "worktree-root");
    defer tree.destroy();

    try tree.write("linked/.git", "gitdir: /elsewhere/.git/worktrees/linked\n");
    try tree.makeDirectory("checkout/.git");
    try tree.makeDirectory("plain");

    try std.testing.expect(discover.isWorktreeRoot(tree.io, tree.dir, "linked"));
    try std.testing.expect(!discover.isWorktreeRoot(tree.io, tree.dir, "checkout"));
    try std.testing.expect(!discover.isWorktreeRoot(tree.io, tree.dir, "plain"));
}

test "collect finds every simulation in path order" {
    var tree = try Tree.create(std.testing.allocator, "collect-order");
    defer tree.destroy();

    try tree.write("packages/beta/src/thing.sim.zig", "");
    try tree.write("packages/alpha/src/other.sim.zig", "");
    try tree.write("packages/alpha/src/first.sim.zig", "");

    const files = try discover.collect(std.testing.allocator, tree.io, tree.dir, .{}, .simulation);
    defer discover.freeFiles(std.testing.allocator, files);

    try std.testing.expectEqual(@as(usize, 3), files.len);
    try std.testing.expectEqualStrings("packages/alpha/src", files[0].directory);
    try std.testing.expectEqualStrings("first.sim.zig", files[0].name);
    try std.testing.expectEqualStrings("packages/alpha/src", files[1].directory);
    try std.testing.expectEqualStrings("other.sim.zig", files[1].name);
    try std.testing.expectEqualStrings("packages/beta/src", files[2].directory);
}

test "collect walks past a dot directory, an ignored one and a linked worktree" {
    var tree = try Tree.create(std.testing.allocator, "collect-skips");
    defer tree.destroy();

    try tree.write(".gitignore", "ignored\n");
    try tree.write("packages/kept/src/kept.sim.zig", "");
    try tree.write(".hidden/packages/hidden/src/hidden.sim.zig", "");
    try tree.write("ignored/packages/ignored/src/ignored.sim.zig", "");
    try tree.write("linked/.git", "gitdir: /elsewhere\n");
    try tree.write("linked/packages/linked/src/linked.sim.zig", "");

    const files = try discover.collect(std.testing.allocator, tree.io, tree.dir, .{}, .simulation);
    defer discover.freeFiles(std.testing.allocator, files);

    try std.testing.expectEqual(@as(usize, 1), files.len);
    try std.testing.expectEqualStrings("packages/kept/src", files[0].directory);
}

test "collect comes back empty when there is nothing to find" {
    var tree = try Tree.create(std.testing.allocator, "collect-empty");
    defer tree.destroy();

    try tree.write("packages/thing/src/thing.zig", "");

    const files = try discover.collect(std.testing.allocator, tree.io, tree.dir, .{}, .simulation);
    defer discover.freeFiles(std.testing.allocator, files);
    try std.testing.expectEqual(@as(usize, 0), files.len);
}

test "stringLiteralsIn takes each literal once and leaves the ones nothing can compare against" {
    var tree = try Tree.create(std.testing.allocator, "literals");
    defer tree.destroy();

    const source =
        "const a = \"ok\";\n" ++
        "const b = \"ok\";\n" ++
        "const c = \"an \\\"escaped\\\" quote\";\n" ++
        "const d = \"\";\n" ++
        "const e = \"" ++ ("x" ** 300) ++ "\";\n" ++
        "const f = \"street_address\";\n";
    try tree.write("module.zig", source);

    const literals = try discover.stringLiteralsIn(std.testing.allocator, tree.io, tree.dir, "module.zig");
    defer discover.freeNames(std.testing.allocator, literals);

    try std.testing.expectEqual(@as(usize, 2), literals.len);
    try std.testing.expectEqualStrings("ok", literals[0]);
    try std.testing.expectEqualStrings("street_address", literals[1]);
}

test "stringLiteralsIn stops at the end when a quote is never closed" {
    var tree = try Tree.create(std.testing.allocator, "literals-unclosed");
    defer tree.destroy();

    try tree.write("module.zig", "const a = \"kept\";\n// a stray \" runs to the end\n");

    const literals = try discover.stringLiteralsIn(std.testing.allocator, tree.io, tree.dir, "module.zig");
    defer discover.freeNames(std.testing.allocator, literals);

    try std.testing.expectEqual(@as(usize, 1), literals.len);
    try std.testing.expectEqualStrings("kept", literals[0]);
}

test "namespaceName flattens a directory into an identifier" {
    const allocator = std.testing.allocator;

    const nested = try discover.namespaceName(allocator, "packages/text/src");
    defer allocator.free(nested);
    try std.testing.expectEqualStrings("sim_packages_text_src", nested);

    const dotted = try discover.namespaceName(allocator, "apps/web.app");
    defer allocator.free(dotted);
    try std.testing.expectEqualStrings("sim_apps_web_app", dotted);

    const plain = try discover.namespaceName(allocator, "src");
    defer allocator.free(plain);
    try std.testing.expectEqualStrings("sim_src", plain);

    const root = try discover.namespaceName(allocator, "");
    defer allocator.free(root);
    try std.testing.expectEqualStrings("sim_", root);
}

test "joinPath leaves the separator out when the directory is the root" {
    const allocator = std.testing.allocator;

    const below = try discover.joinPath(allocator, "packages/text/src", "format.zig");
    defer allocator.free(below);
    try std.testing.expectEqualStrings("packages/text/src/format.zig", below);

    const at_root = try discover.joinPath(allocator, "", "format.zig");
    defer allocator.free(at_root);
    try std.testing.expectEqualStrings("format.zig", at_root);
}

test "generateRoot writes the whole file, byte for byte" {
    var tree = try Tree.create(std.testing.allocator, "generate-root");
    defer tree.destroy();

    try tree.write("packages/thing/src/thing.zig", "const answer = \"yes\";\n");
    try tree.write("packages/thing/src/thing.sim.zig", "");
    try tree.write("packages/thing/src/thing.test.zig", "");

    const text = try discover.generateRoot(std.testing.allocator, tree.io, tree.dir, .{});
    defer std.testing.allocator.free(text);

    const expected = discover.root_header ++
        \\const sim_packages_thing_src = struct {
        \\    pub const simulations = .{
        \\        .{ .module = "packages/thing/src/thing.zig", .scenarios = @import("packages/thing/src/thing.sim.zig") },
        \\    };
        \\
        \\    pub const modules = .{
        \\        .{ .module = "packages/thing/src/thing.zig", .code = @import("packages/thing/src/thing.zig"), .literals = &[_][]const u8{"yes", }, .reflecting = &[_][]const u8{} },
        \\    };
        \\
        \\    pub const helpers = .{
        \\        .{ .code = @import("packages/thing/src/thing.test.zig") },
        \\    };
        \\
        \\    pub const simulation = sim.standard(@This());
        \\};
        \\
        \\pub const packages = [_]sim.Package{
        \\    .{ .directory = "packages/thing/src", .simulation = sim_packages_thing_src.simulation, .excluded_directories = &[_][]const u8{} },
        \\
    ++ discover.root_footer ++
        \\
        \\test {
        \\    _ = @import("packages/thing/src/thing.sim.zig");
        \\}
        \\
    ;

    try std.testing.expectEqualStrings(expected, text);
}

test "generateRoot names a file at the root without a leading separator" {
    var tree = try Tree.create(std.testing.allocator, "generate-root-at-top");
    defer tree.destroy();

    try tree.write("thing.zig", "");
    try tree.write("thing.sim.zig", "");

    const text = try discover.generateRoot(std.testing.allocator, tree.io, tree.dir, .{ .source_directories = &.{""} });
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "@import(\"thing.sim.zig\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@import(\"/thing") == null);
}

test "writeRootIfChanged writes when there is nothing there, and again when the text differs" {
    var tree = try Tree.create(std.testing.allocator, "write-root");
    defer tree.destroy();

    try tree.write("packages/thing/src/thing.zig", "");
    try tree.write("packages/thing/src/thing.sim.zig", "");

    try discover.writeRootIfChanged(std.testing.allocator, tree.io, tree.dir, .{}, "sim_root.zig");
    const first = try tree.read("sim_root.zig");
    defer std.testing.allocator.free(first);
    try std.testing.expect(first.len != 0);

    try tree.write("packages/thing/src/other.sim.zig", "");
    try discover.writeRootIfChanged(std.testing.allocator, tree.io, tree.dir, .{}, "sim_root.zig");
    const second = try tree.read("sim_root.zig");
    defer std.testing.allocator.free(second);
    try std.testing.expect(!std.mem.eql(u8, first, second));
}

test "writeRootIfChanged leaves the file alone when the text is the same" {
    var tree = try Tree.create(std.testing.allocator, "write-root-unchanged");
    defer tree.destroy();

    try tree.write("packages/thing/src/thing.zig", "");
    try tree.write("packages/thing/src/thing.sim.zig", "");

    try discover.writeRootIfChanged(std.testing.allocator, tree.io, tree.dir, .{}, "sim_root.zig");
    const before = try tree.dir.statFile(tree.io, "sim_root.zig", .{});

    try discover.writeRootIfChanged(std.testing.allocator, tree.io, tree.dir, .{}, "sim_root.zig");
    const after = try tree.dir.statFile(tree.io, "sim_root.zig", .{});

    try std.testing.expectEqual(before.mtime, after.mtime);
}

test "detectSourceDirectories finds the highest directory holding code and nothing below it" {
    var tree = try Tree.create(std.testing.allocator, "detect");
    defer tree.destroy();

    try tree.write("build.zig", "");
    try tree.write("source/thing.zig", "");
    try tree.write("source/deeper/other.zig", "");
    try tree.write("apps/cli/main.zig", "");
    try tree.write("docs/notes.md", "");

    const directories = try discover.detectSourceDirectories(std.testing.allocator, tree.io, tree.dir, .{});
    defer discover.freeNames(std.testing.allocator, directories);

    try std.testing.expectEqual(@as(usize, 2), directories.len);
    try std.testing.expectEqualStrings("apps/cli", directories[0]);
    try std.testing.expectEqualStrings("source", directories[1]);
}

test "detectSourceDirectories takes the root itself when the code is there" {
    var tree = try Tree.create(std.testing.allocator, "detect-at-root");
    defer tree.destroy();

    try tree.write("build.zig", "");
    try tree.write("main.zig", "");

    const directories = try discover.detectSourceDirectories(std.testing.allocator, tree.io, tree.dir, .{});
    defer discover.freeNames(std.testing.allocator, directories);

    try std.testing.expectEqual(@as(usize, 1), directories.len);
    try std.testing.expectEqualStrings("", directories[0]);
}

test "detectSourceDirectories finds nothing where there is no code to fault test" {
    var tree = try Tree.create(std.testing.allocator, "detect-nothing");
    defer tree.destroy();

    try tree.write("build.zig", "");
    try tree.write("thing.test.zig", "");
    try tree.write("docs/notes.md", "");

    const directories = try discover.detectSourceDirectories(std.testing.allocator, tree.io, tree.dir, .{});
    defer discover.freeNames(std.testing.allocator, directories);

    try std.testing.expectEqual(@as(usize, 0), directories.len);
}

test "a walk leaves out a directory the project excluded" {
    var tree = try Tree.create(std.testing.allocator, "excluded-directory");
    defer tree.destroy();

    try tree.write("src/thing.zig", "");
    try tree.write("perf-tests/run.zig", "");

    const layout = discover.Layout{
        .source_directories = &.{ "src", "perf-tests" },
        .excluded_directories = &.{"perf-tests"},
    };
    const found = try discover.collect(std.testing.allocator, tree.io, tree.dir, layout, .source);
    defer discover.freeFiles(std.testing.allocator, found);

    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("src", found[0].directory);
}

test "detection leaves out a directory the project excluded" {
    // A benchmark directory holds code, so detection takes it for source and asks for every one of
    // its paths to be covered. It exercises the code rather than being the code exercised.
    var tree = try Tree.create(std.testing.allocator, "excluded-detection");
    defer tree.destroy();

    try tree.write("src/thing.zig", "");
    try tree.write("perf-tests/run.zig", "");

    const found = try discover.detectSourceDirectories(std.testing.allocator, tree.io, tree.dir, .{
        .excluded_directories = &.{"perf-tests"},
    });
    defer discover.freeNames(std.testing.allocator, found);

    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("src", found[0]);
}

test "the generated root carries the excluded names into the run" {
    // The build uses them to decide what to compile in; the run walks the tree again to read the
    // source a checklist is built from. Without them there, that second walk builds a checklist for
    // a file nothing was compiled to exercise, and the run asks for paths no scenario can ever reach.
    var tree = try Tree.create(std.testing.allocator, "excluded-in-root");
    defer tree.destroy();

    try tree.write("src/thing.zig", "");
    try tree.write("src/test/harness.zig", "");

    const text = try discover.generateRoot(std.testing.allocator, tree.io, tree.dir, .{
        .source_directories = &.{"src"},
        .excluded_directories = &.{"test"},
    });
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, ".excluded_directories = &[_][]const u8{\"test\", }"));
}

test "a file naming the testing allocator outside a test cannot be built into the run" {
    var tree = try Tree.create(std.testing.allocator, "testing-allocator-outside");
    defer tree.destroy();

    try tree.write("support.zig", "const std = @import(\"std\");\npub const gpa = std.testing.allocator;\n");

    try std.testing.expect(try discover.usesTestingOutsideTests(std.testing.allocator, tree.io, tree.dir, "support.zig"));
}

test "a file naming the testing allocator only inside its tests is code to exercise" {
    var tree = try Tree.create(std.testing.allocator, "testing-allocator-inside");
    defer tree.destroy();

    try tree.write("thing.zig",
        \\const std = @import("std");
        \\pub fn one() u8 {
        \\    return 1;
        \\}
        \\test "one" {
        \\    try std.testing.expectEqual(@as(u8, 1), one());
        \\    const held = try std.testing.allocator.alloc(u8, 1);
        \\    std.testing.allocator.free(held);
        \\}
        \\
    );

    try std.testing.expect(!try discover.usesTestingOutsideTests(std.testing.allocator, tree.io, tree.dir, "thing.zig"));
}

test "the testing allocator named inside a string or a comment is not a use of it" {
    var tree = try Tree.create(std.testing.allocator, "testing-allocator-written-about");
    defer tree.destroy();

    try tree.write("about.zig",
        \\const std = @import("std");
        \\// std.testing.allocator is what a test uses.
        \\pub const marker = "std.testing.allocator";
        \\
    );

    try std.testing.expect(!try discover.usesTestingOutsideTests(std.testing.allocator, tree.io, tree.dir, "about.zig"));
}

test "a function that reflects on its own type parameter is named so the run leaves it alone" {
    var tree = try Tree.create(std.testing.allocator, "reflecting-functions");
    defer tree.destroy();

    try tree.write("generic.zig",
        \\const std = @import("std");
        \\
        \\// Only ever a return type, so a stand-in works and the run can exercise it.
        \\pub fn passThrough(comptime ReturnT: type, value: ReturnT) ReturnT {
        \\    return value;
        \\}
        \\
        \\// Reads the type's declarations, so no stand-in satisfies it.
        \\pub fn firstDeclaration(comptime Namespace: type) []const u8 {
        \\    return @typeInfo(Namespace).@"struct".decls[0].name;
        \\}
        \\
        \\// Reflects in its return type and nowhere else.
        \\pub fn oneField(comptime Enum: type) [@typeInfo(Enum).@"enum".fields.len]u8 {
        \\    return undefined;
        \\}
        \\
        \\// Hands the parameter to another function, which is where the reflection happens.
        \\pub fn askAnother(comptime Namespace: type) []const u8 {
        \\    return firstDeclaration(Namespace);
        \\}
        \\
        \\// A builtin that works whatever the type is says nothing either way.
        \\pub fn howBig(comptime T: type) usize {
        \\    return @sizeOf(T);
        \\}
        \\
        \\// Hands the parameter to a function in this file that only names it as a return type,
        \\// so the stand-in reaches the bottom unread and this can be exercised.
        \\pub fn passItOn(comptime ReturnT: type, value: ReturnT) ReturnT {
        \\    return passThrough(ReturnT, value);
        \\}
        \\
    );

    const found = try discover.reflectingFunctionsIn(std.testing.allocator, tree.io, tree.dir, "generic.zig");
    defer discover.freeNames(std.testing.allocator, found);

    try std.testing.expectEqual(@as(usize, 3), found.len);
    try std.testing.expectEqualStrings("firstDeclaration", found[0]);
    try std.testing.expectEqualStrings("oneField", found[1]);
    try std.testing.expectEqualStrings("askAnother", found[2]);
}
