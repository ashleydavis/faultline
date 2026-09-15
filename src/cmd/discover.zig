// Finding what to fault test, and generating the root file that exercises it.
//
// A repository is not told what to simulate: the tree is walked, every `<module>.sim.zig` in it is
// found, and the root file that imports them all is generated from what was found. So a simulation
// is picked up by existing, and nothing anywhere carries a list of names, directories or functions
// that goes stale the day one is added, renamed, moved or removed.
//
// Everything here takes an allocator and a directory rather than reaching for a build graph, so it
// can be pointed at a fixture tree and asserted on.

const std = @import("std");

// Which files a repository's code lives in, and which of them are fault tested. The defaults are the
// `packages/<name>/src` arrangement, so a repository laid out that way needs none of this; a
// repository laid out otherwise says so once and is fault tested the same way.
pub const Layout = struct {
    // What a source directory's path has to start with. The default is the arrangement this
    // framework was extracted from, where every package's code is under `packages/<name>/src`.
    source_prefix: []const u8 = "packages/",

    // What a source directory's path has to end with, for the same reason.
    source_suffix: []const u8 = "/src",

    // What a module's own simulation file is called: a file named for the module it exercises, beside
    // it. This is the tool's own naming convention rather than any repository's, which is why it
    // has a default at all.
    simulation_suffix: []const u8 = ".sim.zig",

    // What a test file is called. A test is not code to be fault tested, so it is left out.
    test_suffix: []const u8 = ".test.zig",

    // What a simulation's own test file is called. It is neither a module nor a simulation, and it
    // is reached through the generated root's `test` block rather than by being fault tested.
    simulation_test_suffix: []const u8 = ".sim.test.zig",

    // Name prefixes that are not code to be fault tested. `fuzz_` by default, because a fuzz entry
    // point is a harness that exercises the code rather than code somebody wrote to be exercised.
    excluded_name_prefixes: []const []const u8 = &.{"fuzz_"},

    // Files that are never code to be fault tested whatever directory they sit in: a build script, its
    // manifest, and the root this module generates, which imports every module and would import
    // itself if it were taken for one.
    excluded_names: []const []const u8 = &.{ "build.zig", "build.zig.zon", generated_root_name },

    // Modules the repository supplies with `--module`, each a name and the file it is rooted at.
    // A file that belongs to one of these is reached by its module name: Zig refuses to have one
    // file in two modules, so importing it by path as well would be the same file twice.
    supplied_modules: []const SuppliedModule = &.{},

    // Directories to leave out of the walk entirely, by path from the repository root. A project's
    // benchmarks and its test harnesses are code, so the walk takes them for source and asks for
    // every one of their paths to be covered, which is work nobody wants: a harness is what exercises
    // the code rather than the code being exercised. Nothing in a tree says which is which, so the
    // project says.
    excluded_directories: []const []const u8 = &.{},

    // The directories holding the code to fault test, named rather than matched. Null means match on
    // `source_prefix` and `source_suffix` instead, which is what a repository laid out that way
    // wants. A repository that is not gets these filled in, either from the command line or from
    // what `detectSourceDirectories` found.
    source_directories: ?[]const []const u8 = null,
};

// What the generated root is called. Written once, here, because the walk has to leave it out of
// what it fault tests and the command has to write it.
pub const generated_root_name = "sim_root.zig";

// A module the repository supplies, and the file it is rooted at.
pub const SuppliedModule = struct {
    name: []const u8,
    path: []const u8,
};

// The module a file belongs to, where the repository supplied one rooted in that file's own
// directory. Everything under a module's root directory is that module's, so a file beside the
// root belongs to it too.
pub fn moduleOwning(layout: Layout, path: []const u8) ?SuppliedModule {
    for (layout.supplied_modules) |module| {
        const directory = std.fs.path.dirname(module.path) orelse continue;
        if (std.mem.eql(u8, module.path, path)) {
            return module;
        }
        if (std.mem.startsWith(u8, path, directory) and
            path.len > directory.len and
            path[directory.len] == '/')
        {
            return module;
        }
    }
    return null;
}

// Which files a walk is looking for: the simulation beside a module, the modules themselves, or a
// package's own test-only helpers.
pub const FileKind = enum { simulation, source, helper };

// One file the walk found: the directory it sits in and its own name, kept apart so the generated
// file can group a directory's files together under one namespace.
pub const SimulationFile = struct {
    directory: []const u8,
    name: []const u8,
};

// Whether a file is the kind being looked for. A source module is any `.zig` that is not a test and
// not a simulation, under a source directory: that is where the code a run fault tests lives, and the
// framework's own files and a build script are not it.
pub fn wanted(layout: Layout, kind: FileKind, directory: []const u8, name: []const u8) bool {
    if (!std.mem.endsWith(u8, name, ".zig")) {
        return false;
    }
    for (layout.excluded_names) |excluded| {
        if (std.mem.eql(u8, name, excluded)) {
            return false;
        }
    }
    const in_source_directory = if (layout.source_directories) |directories|
        isUnderOneOf(directories, directory)
    else
        std.mem.startsWith(u8, directory, layout.source_prefix) and
            std.mem.endsWith(u8, directory, layout.source_suffix);
    return switch (kind) {
        // Under a source directory, like every other kind. Without that, a `.sim.zig` anywhere in
        // the tree was compiled into the run: one sitting in a documentation directory beside a
        // scratch file that no longer existed stopped a whole repository being fault tested, with a
        // compiler error about a file nobody had asked to be compiled.
        .simulation => in_source_directory and
            std.mem.endsWith(u8, name, layout.simulation_suffix),
        // A helper is a package's own test-only file. Nothing fault tests it, but what wires a value
        // to somewhere a run can read is kept there, so the run has to be able to see it.
        .helper => in_source_directory and
            std.mem.endsWith(u8, name, layout.test_suffix) and
            !std.mem.endsWith(u8, name, layout.simulation_test_suffix),
        // The same exclusions the run itself applies when it decides which files hold the code
        // somebody wrote: a simulation, a test and an excluded entry point are none of them.
        .source => in_source_directory and
            !std.mem.endsWith(u8, name, layout.simulation_suffix) and
            !std.mem.endsWith(u8, name, layout.test_suffix) and
            !hasExcludedPrefix(layout, name),
    };
}

// Whether `directory` is one of `directories` or sits below one of them. A named source directory
// covers what is under it, so a repository that groups its code into subdirectories names the top
// one and is fault tested all the way down.
pub fn isUnderOneOf(directories: []const []const u8, directory: []const u8) bool {
    for (directories) |candidate| {
        if (std.mem.eql(u8, candidate, directory)) {
            return true;
        }
        if (candidate.len == 0) {
            // The repository root, which everything is under.
            return true;
        }
        if (directory.len > candidate.len and
            std.mem.startsWith(u8, directory, candidate) and
            directory[candidate.len] == '/')
        {
            return true;
        }
    }
    return false;
}

// Whether a name starts with any of the layout's excluded prefixes.
fn hasExcludedPrefix(layout: Layout, name: []const u8) bool {
    for (layout.excluded_name_prefixes) |prefix| {
        if (std.mem.startsWith(u8, name, prefix)) {
            return true;
        }
    }
    return false;
}

// The directories a walk stays out of, read from `.gitignore` rather than listed here: what is not
// ours to build (a cache, a package download, a build output, a dependency tree) is already named
// there, so this stays right when one is added and never needs a second list to be kept in step.
// Only plain directory names are taken; a pattern is left to git.
//
// The caller owns what comes back, and `freeNames` releases it.
pub fn ignoredDirectoryNames(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }

    const source = root.readFileAlloc(io, ".gitignore", allocator, .unlimited) catch
        return names.toOwnedSlice(allocator);
    defer allocator.free(source);

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }
        const name = std.mem.trim(u8, trimmed, "/");
        if (name.len == 0 or std.mem.indexOfAny(u8, name, "*?[!") != null or std.mem.indexOfScalar(u8, name, '/') != null) {
            continue;
        }
        try names.append(allocator, try allocator.dupe(u8, name));
    }

    return names.toOwnedSlice(allocator);
}

// Releases a list of names this module handed back.
pub fn freeNames(allocator: std.mem.Allocator, names: []const []const u8) void {
    for (names) |name| allocator.free(name);
    allocator.free(names);
}

// Whether `name` is one of the ignored directory names.
pub fn isIgnored(ignored: []const []const u8, name: []const u8) bool {
    for (ignored) |entry| {
        if (std.mem.eql(u8, entry, name)) {
            return true;
        }
    }
    return false;
}

// Whether `relative` is the root of a linked git worktree: one whose own `.git` is a file naming
// where the real one lives, rather than a directory. A linked worktree for a branch in progress can
// sit nested inside a checkout, its code mid-edit until that branch merges, so walking into it
// counted an unfinished module's annotations as this tree's own and failed coverage on paths only
// that worktree's own run, made from inside it, is answerable for.
pub fn isWorktreeRoot(io: std.Io, root: std.Io.Dir, relative: []const u8) bool {
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const git_path = std.fmt.bufPrint(&buffer, "{s}/.git", .{relative}) catch return false;
    const stat = root.statFile(io, git_path, .{}) catch return false;
    return stat.kind == .file;
}

// Every file of `kind` under `root`, in path order so two runs over the same tree produce the same
// binary. Nothing says where to look: the whole tree is walked, so a simulation anywhere is picked
// up exactly as one under the source prefix is, and a package that has not been simulated yet is
// skipped rather than reported (that it has work outstanding is not this tool's to have an opinion
// about).
//
// The caller owns what comes back, and `freeFiles` releases it.
pub fn collect(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, layout: Layout, kind: FileKind) ![]SimulationFile {
    const ignored = try ignoredDirectoryNames(allocator, io, root);
    defer freeNames(allocator, ignored);

    var found: std.ArrayList(SimulationFile) = .empty;
    errdefer {
        for (found.items) |file| {
            allocator.free(file.directory);
            allocator.free(file.name);
        }
        found.deinit(allocator);
    }

    try collectInto(allocator, io, root, layout, kind, "", ignored, &found);

    std.mem.sort(SimulationFile, found.items, {}, struct {
        fn lessThan(_: void, a: SimulationFile, other: SimulationFile) bool {
            if (!std.mem.eql(u8, a.directory, other.directory)) {
                return std.mem.lessThan(u8, a.directory, other.directory);
            }
            return std.mem.lessThan(u8, a.name, other.name);
        }
    }.lessThan);

    return found.toOwnedSlice(allocator);
}

// Releases a list of files this module handed back.
pub fn freeFiles(allocator: std.mem.Allocator, files: []const SimulationFile) void {
    for (files) |file| {
        allocator.free(file.directory);
        allocator.free(file.name);
    }
    allocator.free(files);
}

fn collectInto(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    layout: Layout,
    kind: FileKind,
    relative: []const u8,
    ignored: []const []const u8,
    found: *std.ArrayList(SimulationFile),
) !void {
    const path = if (relative.len == 0) "." else relative;

    var dir = try root.openDir(io, path, .{ .iterate = true });
    defer dir.close(io);

    var entries = dir.iterate();
    while (try entries.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                if (std.mem.startsWith(u8, entry.name, ".")) {
                    continue;
                }
                if (isIgnored(ignored, entry.name)) {
                    continue;
                }
                if (isIgnored(layout.excluded_directories, entry.name)) {
                    continue;
                }
                const below = if (relative.len == 0)
                    try allocator.dupe(u8, entry.name)
                else
                    try std.fmt.allocPrint(allocator, "{s}/{s}", .{ relative, entry.name });
                defer allocator.free(below);
                if (isWorktreeRoot(io, root, below)) {
                    continue;
                }
                try collectInto(allocator, io, root, layout, kind, below, ignored, found);
            },
            .file => {
                if (!wanted(layout, kind, relative, entry.name)) {
                    continue;
                }
                const directory = try allocator.dupe(u8, relative);
                errdefer allocator.free(directory);
                const name = try allocator.dupe(u8, entry.name);
                errdefer allocator.free(name);
                try found.append(allocator, .{ .directory = directory, .name = name });
            },
            else => {},
        }
    }
}

// How long a string literal can be before the scan below decides it is not a value worth trying.
// 200 bytes because a branch turns on a status, a type name or a key, and nothing that long is one
// of those; anything longer is a message, a comment's text read by mistake, or embedded data.
const longest_useful_literal = 200;

// Every plain double-quoted string in a file, in the order it appears, with duplicates dropped.
// Scanned rather than parsed: what is wanted is a corpus of values to try, so a literal misread as
// two, or a comment's text taken for one, costs a wasted call and nothing else.
//
// The caller owns what comes back, and `freeNames` releases it.
// The functions in one file that are generic over a type and then reflect on it: the parameter is
// asked for its declarations, its fields or its enum values rather than only naming a type. A run
// exercises a generic function by instantiating it with a stand-in type, and no stand-in satisfies a
// body like that. Instantiating one anyway does not produce a call that finds nothing: it is a
// compile error in the run's own binary, which stops the whole repository being fault tested. This
// walk finds them so the run leaves them alone.
//
// Read from the tokens, because a signature does not carry it. `comptime T: type` looks the same
// whether the body returns a `T` or reads `T`'s declarations, and `@typeInfo` cannot tell them
// apart. The tool's own `nameOf`, `tallyOf`, `failuresFrom`, `nameToEnum`, `everyScenario`,
// `everySeedScenario` and `everyExploration` are all of the second kind, found by fault testing it.
//
// A parameter handed on to another function in the same file is followed there rather than counted
// on the spot: `retry` passes its return type to `retryOnce`, which only names it as a return type,
// and refusing that would leave a function nothing exercises for no reason.
//
// It errs one way on purpose. A parameter handed to a builtin that works whatever the type is does
// not count; a call this walk cannot resolve does. A function wrongly refused here is reported as
// one nothing exercised, which somebody can see and answer; one wrongly let through stops the build.
//
// The caller owns what comes back.
pub fn reflectingFunctionsIn(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, path: []const u8) ![]const []const u8 {
    const source = root.readFileAllocOptions(io, path, allocator, .unlimited, .of(u8), 0) catch return &.{};
    defer allocator.free(source);

    var tokens: std.ArrayList(std.zig.Token) = .empty;
    defer tokens.deinit(allocator);
    var tokenizer = std.zig.Tokenizer.init(source);
    while (true) {
        const token = tokenizer.next();
        try tokens.append(allocator, token);
        if (token.tag == .eof) {
            break;
        }
    }

    var functions = try readFunctions(allocator, source, tokens.items);
    defer freeFunctions(allocator, &functions);

    try settleReflection(allocator, functions.items);

    var found: std.ArrayList([]const u8) = .empty;
    errdefer freeNames(allocator, found.items);
    for (functions.items) |function| {
        var reflects = false;
        for (function.parameters.items) |parameter| {
            if (parameter.is_a_type and parameter.reflected) {
                reflects = true;
            }
        }
        if (!reflects) {
            continue;
        }
        var already = false;
        for (found.items) |seen| {
            if (std.mem.eql(u8, seen, function.name)) {
                already = true;
            }
        }
        if (!already) {
            try found.append(allocator, try allocator.dupe(u8, function.name));
        }
    }
    return found.toOwnedSlice(allocator);
}

// One parameter of one function, as the walk needs it: its name, whether it is a `comptime` type,
// and whether anything the function does with it needs a real type rather than a stand-in.
const Parameter = struct {
    name: []const u8,
    is_a_type: bool,
    reflected: bool = false,
};

// One parameter of this function handed to another function, at the position that other function
// takes it. Following these is what tells a parameter passed straight through from one reflected on.
const Handover = struct {
    parameter: usize,
    callee: []const u8,
    argument: usize,
};

const Function = struct {
    name: []const u8,
    parameters: std.ArrayList(Parameter),
    handovers: std.ArrayList(Handover),
};

fn freeFunctions(allocator: std.mem.Allocator, functions: *std.ArrayList(Function)) void {
    for (functions.items) |*function| {
        function.parameters.deinit(allocator);
        function.handovers.deinit(allocator);
    }
    functions.deinit(allocator);
}

// Every function the file declares, with its parameters and what it does with them. Names point
// into `source`, which the caller holds for as long as the result is used.
fn readFunctions(allocator: std.mem.Allocator, source: [:0]const u8, tokens: []const std.zig.Token) !std.ArrayList(Function) {
    var functions: std.ArrayList(Function) = .empty;
    errdefer freeFunctions(allocator, &functions);

    var at: usize = 0;
    while (at < tokens.len) : (at += 1) {
        if (tokens[at].tag != .keyword_fn) {
            continue;
        }
        // A function type rather than a declaration: no name, and nothing exercises it.
        if (at + 2 >= tokens.len or tokens[at + 1].tag != .identifier or tokens[at + 2].tag != .l_paren) {
            continue;
        }

        var function: Function = .{
            .name = textOf(source, tokens[at + 1]),
            .parameters = .empty,
            .handovers = .empty,
        };
        errdefer {
            function.parameters.deinit(allocator);
            function.handovers.deinit(allocator);
        }

        var after = at + 3;
        var parens: usize = 1;
        var comptime_next = false;
        while (after < tokens.len and parens > 0) : (after += 1) {
            switch (tokens[after].tag) {
                .l_paren => parens += 1,
                .r_paren => parens -= 1,
                .keyword_comptime => comptime_next = true,
                .identifier => {
                    // A parameter is `<name>:` at the top level of the list. Anything else here is
                    // part of a type, which the name before it already accounted for.
                    if (parens == 1 and after + 1 < tokens.len and tokens[after + 1].tag == .colon) {
                        const named_a_type = comptime_next and after + 2 < tokens.len and
                            tokens[after + 2].tag == .identifier and
                            std.mem.eql(u8, textOf(source, tokens[after + 2]), "type");
                        try function.parameters.append(allocator, .{
                            .name = textOf(source, tokens[after]),
                            .is_a_type = named_a_type,
                        });
                        comptime_next = false;
                    }
                },
                .comma => comptime_next = false,
                else => {},
            }
        }

        // Back to just past the name, so a function declared inside this one's body is read too.
        at += 1;

        var holds_a_type = false;
        for (function.parameters.items) |parameter| {
            if (parameter.is_a_type) {
                holds_a_type = true;
            }
        }
        if (!holds_a_type) {
            function.parameters.deinit(allocator);
            function.handovers.deinit(allocator);
            continue;
        }

        // From the end of the parameter list to the end of the body, which takes in the return
        // type: `failuresFrom` reflects on its parameter there and nowhere else.
        try readUses(allocator, source, tokens, after, &function);
        try functions.append(allocator, function);
    }

    return functions;
}

// What one function does with its type parameters, from the end of its parameter list to the end of
// its body.
fn readUses(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
    tokens: []const std.zig.Token,
    from: usize,
    function: *Function,
) !void {
    // One entry per open parenthesis. A parenthesis that only groups an expression has no callee.
    const Call = struct {
        callee: ?[]const u8,
        builtin: bool,
        any_type: bool,
        argument: usize,
    };
    var calls: std.ArrayList(Call) = .empty;
    defer calls.deinit(allocator);

    var braces: usize = 0;
    var body_started = false;
    var at = from;
    while (at < tokens.len) : (at += 1) {
        switch (tokens[at].tag) {
            .eof => return,
            .l_brace => {
                braces += 1;
                body_started = true;
            },
            .r_brace => {
                if (braces == 0) {
                    return;
                }
                braces -= 1;
                if (body_started and braces == 0) {
                    return;
                }
            },
            .semicolon => {
                // A declaration with no body: there is nothing to read.
                if (!body_started) {
                    return;
                }
            },
            .comma => {
                if (calls.items.len > 0) {
                    calls.items[calls.items.len - 1].argument += 1;
                }
            },
            .l_paren => {
                const before = tokens[at - 1];
                const calling = before.tag == .identifier or before.tag == .builtin;
                try calls.append(allocator, .{
                    .callee = if (calling) textOf(source, before) else null,
                    .builtin = before.tag == .builtin,
                    .any_type = before.tag == .builtin and worksForAnyType(textOf(source, before)),
                    .argument = 0,
                });
            },
            .r_paren => {
                if (calls.items.len > 0) {
                    _ = calls.pop();
                }
            },
            .identifier => {
                const index = parameterNamed(function.*, textOf(source, tokens[at])) orelse continue;
                if (!function.parameters.items[index].is_a_type) {
                    continue;
                }
                // Asked for something of its own: only a real type has declarations.
                if (at + 1 < tokens.len and tokens[at + 1].tag == .period) {
                    function.parameters.items[index].reflected = true;
                    continue;
                }
                if (calls.items.len == 0) {
                    continue;
                }
                const call = calls.items[calls.items.len - 1];
                if (call.callee == null or call.any_type) {
                    continue;
                }
                if (call.builtin) {
                    function.parameters.items[index].reflected = true;
                    continue;
                }
                // An ordinary call: whether this matters depends on what that function does with
                // the argument, which is settled once every function has been read.
                try function.handovers.append(allocator, .{
                    .parameter = index,
                    .callee = call.callee.?,
                    .argument = call.argument,
                });
            },
            else => {},
        }
    }
}

fn parameterNamed(function: Function, name: []const u8) ?usize {
    for (function.parameters.items, 0..) |parameter, index| {
        if (std.mem.eql(u8, parameter.name, name)) {
            return index;
        }
    }
    return null;
}

// Follows every handover until nothing changes. A parameter passed to a function this file does not
// declare is counted as reflected on, because there is no way to see what happens to it there.
fn settleReflection(allocator: std.mem.Allocator, functions: []Function) !void {
    _ = allocator;
    var changed = true;
    while (changed) {
        changed = false;
        for (functions) |function| {
            for (function.handovers.items) |handover| {
                if (function.parameters.items[handover.parameter].reflected) {
                    continue;
                }
                var reflected = true;
                for (functions) |*called| {
                    if (!std.mem.eql(u8, called.name, handover.callee)) {
                        continue;
                    }
                    reflected = handover.argument < called.parameters.items.len and
                        called.parameters.items[handover.argument].reflected;
                }
                if (reflected) {
                    function.parameters.items[handover.parameter].reflected = true;
                    changed = true;
                }
            }
        }
    }
}

// The builtins that take a type and work whatever it is, so handing one a stand-in says nothing
// about whether the function can be exercised.
fn worksForAnyType(name: []const u8) bool {
    for ([_][]const u8{ "@as", "@sizeOf", "@alignOf", "@typeName" }) |builtin| {
        if (std.mem.eql(u8, name, builtin)) {
            return true;
        }
    }
    return false;
}

fn textOf(source: [:0]const u8, token: std.zig.Token) []const u8 {
    return source[token.loc.start..token.loc.end];
}

pub fn stringLiteralsIn(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, path: []const u8) ![]const []const u8 {
    const source = try root.readFileAlloc(io, path, allocator, .unlimited);
    defer allocator.free(source);

    var found: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (found.items) |literal| allocator.free(literal);
        found.deinit(allocator);
    }

    var index: usize = 0;
    while (index < source.len) : (index += 1) {
        if (source[index] != '"') {
            continue;
        }
        var end = index + 1;
        while (end < source.len and source[end] != '"') : (end += 1) {
            // An escape takes the next byte with it, so a quote inside the literal is not its end.
            if (source[end] == '\\') {
                end += 1;
            }
        }
        if (end >= source.len) {
            break;
        }
        const literal = source[index + 1 .. end];
        index = end;
        // A stray quote in a comment makes the scan run to the next one, which can be lines away.
        // A literal with a newline in it, an escape, or more text than any branch compares against
        // is one of those rather than a value worth trying.
        if (literal.len == 0 or literal.len > longest_useful_literal) {
            continue;
        }
        if (std.mem.indexOfAny(u8, literal, "\\\n\r") != null) {
            continue;
        }
        var already = false;
        for (found.items) |seen| {
            if (std.mem.eql(u8, seen, literal)) {
                already = true;
                break;
            }
        }
        if (!already) {
            try found.append(allocator, try allocator.dupe(u8, literal));
        }
    }

    return found.toOwnedSlice(allocator);
}

// Whether a file is valid Zig at all. A repository can hold a file named `.zig` that is not: a
// generated record, a template, something a tool left behind. It cannot be fault tested and it stops
// the whole run compiling, so the walk leaves it out.
pub fn parsesAsZig(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, path: []const u8) !bool {
    const source = root.readFileAllocOptions(io, path, allocator, .unlimited, .of(u8), 0) catch return false;
    defer allocator.free(source);

    var tree = std.zig.Ast.parse(allocator, source, .zig) catch return false;
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) {
        return false;
    }

    // A file whose top level holds anything but declarations is not a Zig module: a list of names,
    // a record, a template. It parses, and then the compiler refuses it as a tuple, which stops the
    // whole run rather than that one file.
    for (tree.rootDecls()) |node| {
        switch (tree.nodeTag(node)) {
            .fn_decl,
            .fn_proto,
            .fn_proto_simple,
            .fn_proto_multi,
            .fn_proto_one,
            .global_var_decl,
            .local_var_decl,
            .simple_var_decl,
            .aligned_var_decl,
            .@"comptime",
            .test_decl,
            => {},
            else => return false,
        }
    }
    return true;
}

// Whether a file reaches for the testing allocator outside a test block. The standard library
// refuses that allocator with a compile error in anything but a test binary, so such a file cannot
// be built into the simulation at all: it is test support rather than code to exercise.
//
// Only the allocator, and only outside a `test` block. A file that merely names `std.testing`
// inside its own tests compiles anywhere, and excluding it would leave its functions unexercised.
//
// Tokenized rather than searched for as text, so the name written inside a string literal or a
// comment is not read as a use of it. The tool's own `discover.zig` holds that name as a literal,
// and searching the bytes dropped every function in the file from the run.
pub fn usesTestingOutsideTests(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, path: []const u8) !bool {
    const source = root.readFileAllocOptions(io, path, allocator, .unlimited, .of(u8), 0) catch return false;
    defer allocator.free(source);

    var tokenizer = std.zig.Tokenizer.init(source);
    // How much of `std` `.` `testing` `.` `allocator` has come through in order. A token that is
    // not the next one wanted starts the count again, from this token where it can begin one.
    var matched: usize = 0;
    // Brace depth, and the depth a `test` block was opened at. Null means the run is not inside
    // one. A test body ends when the depth comes back to where it opened.
    var depth: usize = 0;
    var test_opened_at: ?usize = null;
    var test_pending = false;
    while (true) {
        const token = tokenizer.next();
        const text = source[token.loc.start..token.loc.end];
        switch (token.tag) {
            .eof => return false,
            .keyword_test => {
                test_pending = true;
                matched = 0;
            },
            .l_brace => {
                if (test_pending and test_opened_at == null) {
                    test_opened_at = depth;
                    test_pending = false;
                }
                depth += 1;
                matched = 0;
            },
            .r_brace => {
                depth -|= 1;
                if (test_opened_at) |opened| {
                    if (depth <= opened) {
                        test_opened_at = null;
                    }
                }
                matched = 0;
            },
            .identifier => {
                if (matched == 0 and std.mem.eql(u8, text, "std")) {
                    matched = 1;
                } else if (matched == 2 and std.mem.eql(u8, text, "testing")) {
                    matched = 3;
                } else if (matched == 4 and std.mem.eql(u8, text, "allocator")) {
                    if (test_opened_at == null) {
                        return true;
                    }
                    matched = 0;
                } else {
                    matched = 0;
                }
            },
            .period => {
                if (matched == 1 or matched == 3) {
                    matched += 1;
                } else {
                    matched = 0;
                }
            },
            else => {
                matched = 0;
            },
        }
    }
}

// The namespace one directory's simulation is gathered under in the generated file: where it was
// found, with the separators flattened so it is an identifier, which makes it unique without
// anything having to name a package.
//
// The caller owns what comes back.
pub fn joinPath(allocator: std.mem.Allocator, directory: []const u8, name: []const u8) ![]const u8 {
    if (directory.len == 0) {
        return allocator.dupe(u8, name);
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ directory, name });
}

// The namespace one directory's simulation is gathered under, and the path one of its files is
// imported by. The root directory has an empty name, which is what detection produces for a
// repository whose code sits at the top, so both of these have to read as though it were not there.
pub fn namespaceName(allocator: std.mem.Allocator, directory: []const u8) ![]const u8 {
    const flattened = try allocator.dupe(u8, directory);
    defer allocator.free(flattened);
    for (flattened) |*character| {
        if (!std.ascii.isAlphanumeric(character.*)) {
            character.* = '_';
        }
    }
    return std.fmt.allocPrint(allocator, "sim_{s}", .{flattened});
}

// EXEMPTION, asked for and granted on 2026-09-14: the contract says no embedded code and no source
// built by printing it, and everything from here to the end of `generateRoot` is both.
//
// It is the whole of the exemption, and it exists because Zig resolves `@import` at compile time
// from a path written in the source. The set of files a run exercises is whatever `<module>.sim.zig`
// files are on disk in the repository being fault tested, which is known only once that repository
// has been walked, at run time. No arrangement of Zig can import a list decided then, so a file
// holding that list has to be produced, and producing a Zig file means writing Zig.
//
// What was tried instead: attaching each source file as its own module with `-M`, which needs one
// module per file and a root importing them by name, so the root still has to be generated. Nothing
// else came closer.
//
// The generated root file, around the one line per package the walk produces. It is the whole entry
// point: the run does the arguments, the coverage and the report for every package at once, so
// there is nothing here to keep in step with a package.
pub const root_header =
    \\// Generated from what the walk found. Never edited.
    \\
    \\const sim = @import("sim");
    \\
    \\
;

pub const root_footer =
    \\};
    \\
    \\pub const panic = sim.panic;
    \\pub const main = sim.mainFor(@This());
    \\
;

// The text of the generated root for the tree under `root`, returned rather than written so a test
// can read it.
//
// The caller owns what comes back.
pub fn generateRoot(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, layout: Layout) ![]const u8 {
    const files = try collect(allocator, io, root, layout, .simulation);
    defer freeFiles(allocator, files);
    const modules = try collect(allocator, io, root, layout, .source);
    defer freeFiles(allocator, modules);
    const helpers = try collect(allocator, io, root, layout, .helper);
    defer freeFiles(allocator, helpers);

    var text: std.Io.Writer.Allocating = .init(allocator);
    errdefer text.deinit();
    const writer = &text.writer;

    try writer.writeAll(root_header);

    // A package per source directory, not per simulation file. A repository is exercised because its
    // code is there, so one with no `<module>.sim.zig` anywhere is still exercised in full; a
    // simulation file adds scenarios to a directory that already has a package.
    const directories = try sourceDirectories(allocator, modules);
    defer freeNames(allocator, directories);

    for (directories) |directory| {
        const namespace = try namespaceName(allocator, directory);
        defer allocator.free(namespace);
        try writer.print("const {s} = struct {{\n    pub const simulations = .{{\n", .{namespace});

        // Each entry carries the module its file exercises as well as the file itself. The run ticks a
        // module's coverage only from what its own simulation annotated, and the path here is the
        // only place that pairing is known: the file was found by name, so the module is the same
        // name without the simulation suffix.
        for (files) |file| {
            if (!std.mem.eql(u8, file.directory, directory)) {
                continue;
            }
            const exercised = try joinPath(allocator, directory, file.name[0 .. file.name.len - layout.simulation_suffix.len]);
            defer allocator.free(exercised);
            const path = try joinPath(allocator, directory, file.name);
            defer allocator.free(path);
            if (moduleOwning(layout, path) != null) {
                continue;
            }
            try writer.print(
                "        .{{ .module = \"{s}.zig\", .scenarios = @import(\"{s}\") }},\n",
                .{ exercised, path },
            );
        }

        try writer.writeAll("    };\n\n");

        // Every module in the same directory, so the run can call their functions from their own
        // types without a scenario being written for any of them.
        try writer.writeAll("    pub const modules = .{\n");
        for (modules) |module| {
            if (!std.mem.eql(u8, module.directory, directory)) {
                continue;
            }
            const module_path = try joinPath(allocator, module.directory, module.name);
            defer allocator.free(module_path);

            // A file reaching for `std.testing` outside a test block cannot be compiled into
            // anything but a test binary: the standard library refuses its allocator there. It is
            // test support rather than code to exercise, so the run leaves it out.
            if (try usesTestingOutsideTests(allocator, io, root, module_path)) {
                continue;
            }
            if (!try parsesAsZig(allocator, io, root, module_path)) {
                continue;
            }

            // A file the repository already supplies as a module is reached by that name. Only the
            // module's own root is listed: every other file in it is reached from inside it, and
            // importing one by path would put the same file in two modules, which Zig refuses.
            if (moduleOwning(layout, module_path)) |supplied| {
                if (!std.mem.eql(u8, supplied.path, module_path)) {
                    continue;
                }
                try writer.print(
                    "        .{{ .module = \"{s}\", .code = @import(\"{s}\"), .literals = &[_][]const u8{{",
                    .{ module_path, supplied.name },
                );
            } else {
                try writer.print(
                    "        .{{ .module = \"{s}\", .code = @import(\"{s}\"), .literals = &[_][]const u8{{",
                    .{ module_path, module_path },
                );
            }
            // The strings the module itself is written in terms of. A branch turning on a status
            // being "OK" or a type being "street_address" is reached by trying that exact text, and
            // there is nowhere else it could come from: the module names it, so the run reads it
            // from there rather than being told.
            const literals = try stringLiteralsIn(allocator, io, root, module_path);
            defer freeNames(allocator, literals);
            for (literals) |literal| {
                try writer.print("\"{s}\", ", .{literal});
            }
            // The functions the run has to leave alone, because instantiating them with a stand-in
            // type would not compile. Carried here rather than worked out at run time, since the
            // decision is made from the source and the run only has the types.
            try writer.writeAll("}, .reflecting = &[_][]const u8{");
            const reflecting = try reflectingFunctionsIn(allocator, io, root, module_path);
            defer freeNames(allocator, reflecting);
            for (reflecting) |function| {
                try writer.print("\"{s}\", ", .{function});
            }
            try writer.writeAll("} },\n");
        }
        try writer.writeAll("    };\n\n");

        try writer.writeAll("    pub const helpers = .{\n");
        for (helpers) |helper| {
            if (!std.mem.eql(u8, helper.directory, directory)) {
                continue;
            }
            const helper_path = try joinPath(allocator, directory, helper.name);
            defer allocator.free(helper_path);
            // A helper inside a module the repository supplies is that module's file, reached from
            // inside it. Importing it by path as well would put one file in two modules.
            if (moduleOwning(layout, helper_path) != null) {
                continue;
            }
            try writer.print("        .{{ .code = @import(\"{s}\") }},\n", .{helper_path});
        }
        try writer.writeAll("    };\n\n");

        try writer.writeAll("    pub const simulation = sim.standard(@This());\n};\n\n");
    }

    try writer.writeAll("pub const packages = [_]sim.Package{\n");
    for (directories) |directory| {
        const namespace = try namespaceName(allocator, directory);
        defer allocator.free(namespace);
        // The repository root is named ".", because the run opens this directory to read the
        // package's sources and an empty name is not a directory anything can open.
        const named = if (directory.len == 0) "." else directory;
        try writer.print("    .{{ .directory = \"{s}\", .simulation = {s}.simulation, .excluded_directories = &[_][]const u8{{", .{ named, namespace });
        // The same names the walk above used, carried into the run: it walks the tree again to read
        // the source a checklist is built from, and without these it would build one for a file this
        // walk left out and nothing was compiled to exercise.
        for (layout.excluded_directories) |excluded| {
            try writer.print("\"{s}\", ", .{excluded});
        }
        try writer.writeAll("} },\n");
    }
    try writer.writeAll(root_footer);

    // A file is only compiled, and its own `test` blocks only collected, when something references
    // it. `main` is not analysed in a test build, so without this block every simulation file and
    // every `<module>.sim.test.zig` beside one would be skipped silently by a test build.
    try writer.writeAll("\ntest {\n");
    for (files) |file| {
        const path = try joinPath(allocator, file.directory, file.name);
        defer allocator.free(path);
        try writer.print("    _ = @import(\"{s}\");\n", .{path});
    }
    try writer.writeAll("}\n");

    return text.toOwnedSlice();
}

// Writes the generated root at `path` under `root`, and only when what it should say has changed:
// writing it every run would move its timestamp and make every later step rebuild for nothing.
pub fn writeRootIfChanged(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, layout: Layout, path: []const u8) !void {
    const text = try generateRoot(allocator, io, root, layout);
    defer allocator.free(text);

    const existing = root.readFileAlloc(io, path, allocator, .unlimited) catch null;
    defer if (existing) |already| allocator.free(already);

    if (existing != null and std.mem.eql(u8, existing.?, text)) {
        return;
    }
    try root.writeFile(io, .{ .sub_path = path, .data = text });
}

// Every directory that holds a module, in path order and each named once. This is what a package
// is built from: the code being there is what makes it exercised.
//
// The caller owns what comes back, and `freeNames` releases it.
fn sourceDirectories(allocator: std.mem.Allocator, modules: []const SimulationFile) ![]const []const u8 {
    var found: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (found.items) |name| allocator.free(name);
        found.deinit(allocator);
    }

    for (modules) |module| {
        var already = false;
        for (found.items) |seen| {
            if (std.mem.eql(u8, seen, module.directory)) {
                already = true;
                break;
            }
        }
        if (!already) {
            try found.append(allocator, try allocator.dupe(u8, module.directory));
        }
    }

    return found.toOwnedSlice(allocator);
}

// The directories holding the code to fault test, worked out from the tree when the layout's own
// prefix and suffix match nothing. Every directory that directly holds a `.zig` file which is not a
// test, not a simulation and not excluded, with any directory that sits below another one dropped:
// naming the top one fault tests everything under it, and naming both would fault test it twice.
//
// The caller owns what comes back, and `freeNames` releases it.
pub fn detectSourceDirectories(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir, layout: Layout) ![]const []const u8 {
    const ignored = try ignoredDirectoryNames(allocator, io, root);
    defer freeNames(allocator, ignored);

    var found: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (found.items) |name| allocator.free(name);
        found.deinit(allocator);
    }

    try detectInto(allocator, io, root, layout, "", ignored, &found);

    std.mem.sort([]const u8, found.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    // Sorted, a directory always comes after the one it sits below, so one pass keeps the first of
    // each run and drops the rest.
    var highest: std.ArrayList([]const u8) = .empty;
    errdefer highest.deinit(allocator);
    for (found.items) |candidate| {
        if (isUnderOneOf(highest.items, candidate)) {
            allocator.free(candidate);
            continue;
        }
        try highest.append(allocator, candidate);
    }
    found.deinit(allocator);

    return highest.toOwnedSlice(allocator);
}

fn detectInto(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: std.Io.Dir,
    layout: Layout,
    relative: []const u8,
    ignored: []const []const u8,
    found: *std.ArrayList([]const u8),
) !void {
    const path = if (relative.len == 0) "." else relative;

    var dir = try root.openDir(io, path, .{ .iterate = true });
    defer dir.close(io);

    var holds_source = false;
    var below: std.ArrayList([]const u8) = .empty;
    defer {
        for (below.items) |name| allocator.free(name);
        below.deinit(allocator);
    }

    var entries = dir.iterate();
    while (try entries.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                if (std.mem.startsWith(u8, entry.name, ".")) {
                    continue;
                }
                if (isIgnored(ignored, entry.name)) {
                    continue;
                }
                if (isIgnored(layout.excluded_directories, entry.name)) {
                    continue;
                }
                const child = try joinPath(allocator, relative, entry.name);
                errdefer allocator.free(child);
                if (isWorktreeRoot(io, root, child)) {
                    allocator.free(child);
                    continue;
                }
                try below.append(allocator, child);
            },
            .file => {
                // The same test this asks of a file anywhere else, with the directory taken as a
                // source directory rather than checked against one: that is the question being
                // answered here.
                if (!std.mem.endsWith(u8, entry.name, ".zig")) {
                    continue;
                }
                if (std.mem.endsWith(u8, entry.name, layout.simulation_suffix)) {
                    continue;
                }
                if (std.mem.endsWith(u8, entry.name, layout.test_suffix)) {
                    continue;
                }
                if (hasExcludedPrefix(layout, entry.name)) {
                    continue;
                }
                var excluded = false;
                for (layout.excluded_names) |name| {
                    if (std.mem.eql(u8, name, entry.name)) {
                        excluded = true;
                        break;
                    }
                }
                if (!excluded) {
                    holds_source = true;
                }
            },
            else => {},
        }
    }

    if (holds_source) {
        try found.append(allocator, try allocator.dupe(u8, relative));
        // Everything under a source directory is part of it, so there is nothing left to look for
        // below this one.
        return;
    }

    for (below.items) |child| {
        try detectInto(allocator, io, root, layout, child, ignored, found);
    }
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("discover.test.zig");
}
