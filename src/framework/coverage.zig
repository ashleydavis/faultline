const std = @import("std");
const Ast = std.zig.Ast;

// Reads a function's own source with std.zig.Ast and turns its branches into a checklist a run
// ticks off, rather than a list somebody typed by hand and could let drift from the code.
// Nothing here imports anything from packages/, src/ or apps/ (test/repository_layout.test.zig fails the build
// if it ever does): a branch is named either from its own `if (an) annotate(log, "name", ...)`
// call, recognised as a syntax shape rather than by importing what `annotate` does, or, where a
// branch carries none, from a synthesized name built from its kind, line and side.
//
// What counts as a path: an `if`'s two sides, one entry per `switch` case (`else` included),
// and a loop's body. `if (an) annotate(...)` itself is excluded outright (never a path, whatever
// function it sits in), because it is comptime-known: only one side of it is ever compiled into a
// given build, so there is nothing for a run to choose between.
//
// Only statements are recognised: an `if`, `switch`, `while` or `for` written as one, at any depth
// reached by walking into an `if`'s two sides, a `switch` case's target, or a loop's body. An `if`
// or `switch` used as a value inside a larger expression (a `const x = if (a) b else c;`) is not a
// statement in this sense and is not found.

// Where the function's own entry path sits on every checklist. `build` writes it first, before any
// branch, so anything asking whether the body ran asks at this index.
const entry_path = 0;

// One path through the function under test: where it is, and what a run names it when it ticks.
// `name` is either the string literal inside an `if (an) annotate(log, "<name>", ...)` call found
// in the branch's own body, or, where none is there, a synthesized name built from the branch's
// kind, line and side (`"if:42:true"`, `"switch:50:.connection_refused"`, `"loop:60:zero"`) so
// every branch the parser finds still gets an entry, tickable only by a caller that names it
// directly since nothing in a trace will ever match a name nobody wrote.
pub const Path = struct {
    // The line the branch's own controlling token (`if`, a `switch` case's `=>`, `while`, `for`)
    // sits on, exactly as `build`'s source numbers it from one.
    line: u32,

    // What a run ticks this path by: a real annotation name where the branch has one, otherwise a
    // synthesized name built from its kind, line and side.
    name: []const u8,

    // Whether an annotation can be written on this branch at all. A short-circuit (`and`, `or`)
    // and a `try` are branches with no statement position anywhere in them, so nothing can be
    // emitted when they are taken: they are real paths, counted and listed, but no run can ever
    // tick one, and line coverage over the built binary is what covers them instead. Every other
    // form can hold a statement, or be written so it can, so it is observable and has to be
    // annotated and exercised.
    observable: bool = true,

    // For the side of an `if` that has no `else`: the two names a run counts to decide it ran.
    // Null for every other path.
    not_taken: ?NotTaken = null,
};

// What proves the side of an `if` that has no `else` ran, without a line being written for it.
//
// The function says it was entered, once per call, and the taken side says so once per call that
// took it. Entered more often than taken means some call did not take it, which is the side with
// nowhere to put a marker of its own. Nothing has to be added to the code for this: both names are
// already there, one at the top of the function and one inside the branch.
pub const NotTaken = struct {
    // The name the function emits on the way in.
    entered: []const u8,

    // The name the taken side emits.
    taken: []const u8,
};

// The AST-derived branch list for one function, and which of its paths a run has reached. Every
// string here (`function`, `file`, and each `Path.name`) is owned by this `Checklist`, allocated
// with `allocator`, so `build`'s source and the `Ast` it parsed can be freed the moment it returns.
pub const Checklist = struct {
    // What `deinit` frees everything owned here with.
    allocator: std.mem.Allocator,

    // The function this checklist was built from.
    function: []const u8,

    // The file `function` was read from, printed beside every path so a finding can be opened
    // directly.
    file: []const u8,

    // Every branch `build` found, in the order it found them.
    paths: []Path,

    // Parallel to `paths`: whether a run has reached the path at the same index.
    ticked: []bool,

    pub fn deinit(self: *Checklist) void {
        self.allocator.free(self.function);
        self.allocator.free(self.file);
        for (self.paths) |path| {
            self.allocator.free(path.name);
            if (path.not_taken) |counted| {
                self.allocator.free(counted.entered);
                self.allocator.free(counted.taken);
            }
        }
        self.allocator.free(self.paths);
        self.allocator.free(self.ticked);
    }

    // Marks the path named `name` reached. A name matching nothing the parser found is a drifted
    // call site, not something to silently ignore: reading a function tells a caller exactly which
    // names `build` produced, so this is always a bug in the caller when it happens.
    // Ticks this function's own entry path, the one `build` puts first on every checklist: the
    // scenario that just called the function is the only thing that knows it did, so it says so
    // here rather than the framework assuming it from the subject having returned.
    pub fn tickEntered(self: *Checklist) void {
        var buffer: [256]u8 = undefined;
        const name = std.fmt.bufPrint(&buffer, "{s}:entered", .{self.function}) catch {
            std.debug.panic("The function name \"{s}\" is too long to build its entry path from.", .{self.function});
        };
        self.tick(name);
    }

    // A name this checklist does not carry is ignored rather than fatal: one scenario is run once
    // per function it exercises, so most of what it ticks belongs to another function's checklist.
    // A tick that names nothing anywhere still shows up, as the path it was meant for staying
    // unticked and the run exiting non-zero.
    pub fn tick(self: *Checklist, name: []const u8) void {
        for (self.paths, 0..) |path, index| {
            if (std.mem.eql(u8, path.name, name)) {
                self.ticked[index] = true;
                return;
            }
        }
    }

    // Ticks everything `names` proves, in the order the run recorded it. Every path but a loop's is
    // ticked by its own name appearing anywhere in the list; a loop's zero, one and many paths are
    // ticked by counting, since how many times a loop went round is not something one annotation
    // can say. `names` therefore has to be the run's own order, not a set.
    pub fn tickFromTrace(self: *Checklist, names: []const []const u8) void {
        for (names) |name| {
            self.tick(name);
        }
        for (self.paths, 0..) |path, index| {
            if (self.ticked[index]) {
                continue;
            }
            if (!path.observable) {
                continue;
            }
            if (path.not_taken) |counted| {
                if (ranWithoutTaking(names, counted)) {
                    self.ticked[index] = true;
                    continue;
                }
                // Nothing said the function was entered, so there is no count to compare against
                // and this side cannot be decided either way. Reported as a branch no run can
                // observe rather than one a run missed: a caller cannot make it observable, and
                // asking for work that does not exist is worse than not asking.
                if (timesSaid(names, counted.entered) == 0) {
                    self.paths[index].observable = false;
                }
                continue;
            }
        }
        self.tickEntryFromTheRest();
        self.dropTheEntryNothingCanProve(names);
    }

    // The entry path, when nothing can say the body ran: the run did not call the function itself,
    // no branch of it came back, and the code carries no mark of its own. Left in the report and
    // out of the count, the same as a branch with nowhere to put a mark.
    fn dropTheEntryNothingCanProve(self: *Checklist, names: []const []const u8) void {
        if (self.paths.len == 0 or self.ticked[entry_path]) {
            return;
        }
        if (timesSaid(names, self.paths[entry_path].name) > 0) {
            return;
        }
        self.paths[entry_path].observable = false;
    }

    // The entry path, ticked because one of this function's own branches was. The run says a
    // function was entered for every call it makes itself, which leaves the functions it cannot
    // call: a private one, or one whose arguments it has no factory for, runs only because
    // something else called it. Every other name on this checklist belongs to this function alone,
    // so one of them coming back is proof the body ran.
    fn tickEntryFromTheRest(self: *Checklist) void {
        if (self.paths.len == 0 or self.ticked[entry_path]) {
            return;
        }
        for (self.ticked[entry_path + 1 ..]) |reached| {
            if (reached) {
                self.ticked[entry_path] = true;
                return;
            }
        }
    }

    // Whether some one traversal entered and did not take the side that carries the mark, which is
    // what proves the side with no mark on it ran.
    //
    // Read one traversal at a time rather than by comparing totals. The run says a function was
    // entered once per call it makes itself, and it makes none for a call inside a scenario, so a
    // total of entries and a total of takes count different things: a scenario that took the branch
    // pushed the takes past the entries and the side that ran read as one that never did.
    fn ranWithoutTaking(names: []const []const u8, counted: NotTaken) bool {
        var inside = false;
        var taken_here = false;
        for (names) |name| {
            if (std.mem.eql(u8, name, counted.entered)) {
                if (inside and !taken_here) {
                    return true;
                }
                inside = true;
                taken_here = false;
                continue;
            }
            if (inside and std.mem.eql(u8, name, counted.taken)) {
                taken_here = true;
            }
        }
        return inside and !taken_here;
    }

    // How many times a name was said.
    fn timesSaid(names: []const []const u8, wanted: []const u8) usize {
        var count: usize = 0;
        for (names) |name| {
            if (std.mem.eql(u8, name, wanted)) {
                count += 1;
            }
        }
        return count;
    }

    pub fn tickStrict(self: *Checklist, name: []const u8) void {
        for (self.paths, 0..) |path, index| {
            if (std.mem.eql(u8, path.name, name)) {
                self.ticked[index] = true;
                return;
            }
        }
        std.debug.panic(
            "coverage: tick(\"{s}\") does not name a path in {s}:{s}",
            .{ name, self.file, self.function },
        );
    }

    // Whether every path has been ticked, the condition that ends a coverage search early.
    pub fn allTicked(self: Checklist) bool {
        for (self.ticked) |value| {
            if (!value) {
                return false;
            }
        }
        return true;
    }

    // How many paths have been ticked, which is what a run reports as the coverage it achieved:
    // the question "how many code paths were executed" asked directly rather than inferred from
    // the total and what is left.
    pub fn tickedCount(self: Checklist) usize {
        return self.paths.len - self.untickedCount();
    }

    // How many paths remain unticked, the size of the finding a search prints when it stops with
    // some still open.
    pub fn untickedCount(self: Checklist) usize {
        var count: usize = 0;
        for (self.ticked) |value| {
            if (!value) {
                count += 1;
            }
        }
        return count;
    }

    // Prints every path, ticked or not, naming the function and line: what a reader opens to see
    // which paths a run covered, and what a search prints for whatever is still open when it stops.
    pub fn report(self: Checklist, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print(
            "sim: coverage checklist for {s}:{s}\n",
            .{ self.file, self.function },
        );
        for (self.paths, 0..) |path, index| {
            const mark = if (self.ticked[index]) "ticked" else if (!path.observable) "NO ANNOTATION POSSIBLE" else "UNTICKED";
            try writer.print("  {s} {s}:{d} \"{s}\"\n", .{ mark, self.file, path.line, path.name });
        }
    }
};

// The two ways `build` fails beyond running out of memory: `SourceDoesNotParse` says the text
// handed in was not valid Zig at all, `FunctionNotFound` says it parsed but named no function
// called `function_name`. Named explicitly, along with every function below it calls, because two
// of those functions call each other (an `if`'s body can hold another `if`) and Zig cannot infer
// an error set across a cycle.
const BuildError = std.mem.Allocator.Error || error{ SourceDoesNotParse, FunctionNotFound };

// Parses `source` (a whole file is fine; only `function_name`'s own declaration is read) and
// builds the checklist for that one function's own branches. `source` is only ever read, never
// freed or kept: whatever `Ast.parse` builds from it is freed before this returns, and everything
// the caller keeps out of a `Checklist` is duplicated into `allocator` first, so it never points
// back into `source` or the `Ast`. Always the first declaration named `function_name`: where a
// file has more than one (two structs each with their own method of the same name), use
// `buildOccurrence` instead.
pub fn build(allocator: std.mem.Allocator, file: []const u8, source: [:0]const u8, function_name: []const u8) BuildError!Checklist {
    return buildOccurrence(allocator, file, source, function_name, 0);
}

// The same as `build`, but reads the `occurrence`-th (counting from zero) declaration named
// `function_name` rather than always the first. Needed only where two functions share a name
// because each sits in a different container within the same file, such as `log.zig`'s
// `WriterLog.dispatch` and `RecordingLog.dispatch`: Zig's own name resolution never needs to tell
// them apart, since a caller always reaches one or the other through its own container, but a plain
// name search over the flat node array cannot tell them apart either, and has to be told which one
// is wanted.
pub fn buildOccurrence(allocator: std.mem.Allocator, file: []const u8, source: [:0]const u8, function_name: []const u8, occurrence: usize) BuildError!Checklist {
    var tree = try Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) {
        return error.SourceDoesNotParse;
    }

    const body = findFunctionBody(tree, function_name, occurrence) orelse return error.FunctionNotFound;

    var paths: std.ArrayList(Path) = .empty;
    errdefer {
        for (paths.items) |path| {
            allocator.free(path.name);
        }
        paths.deinit(allocator);
    }

    // A function with an empty body has nothing to run: no statement, no branch, no effect a test
    // could observe. It gets an empty checklist rather than an entry path nothing can ever tick,
    // since the only way to tick one is an annotation, and there is nowhere to put it.
    {
        var statements_buffer: [2]Ast.Node.Index = undefined;
        if (tree.blockStatements(&statements_buffer, body)) |statements| {
            if (statements.len == 0) {
                return .{
                    .allocator = allocator,
                    .file = try allocator.dupe(u8, file),
                    .function = try allocator.dupe(u8, function_name),
                    .paths = try paths.toOwnedSlice(allocator),
                    .ticked = try allocator.alloc(bool, 0),
                };
            }
        }
    }

    // Entry one on every checklist is the function's own body: running it at all is a path through
    // it, and the branches found below are the ways that path can differ. Without this a function
    // with no `if`, `switch` or loop produced an empty checklist and reported "0 of 0", which is
    // wrong twice over: it has one path rather than none, and an empty checklist makes a function
    // nothing ever called indistinguishable from one that ran.
    try paths.append(allocator, .{
        .line = @intCast(tree.tokenLocation(0, tree.firstToken(body)).line + 1),
        .name = try std.fmt.allocPrint(allocator, "{s}:entered", .{function_name}),
    });

    try walkEveryBranch(allocator, tree, body, function_name, &paths);

    const ticked = try allocator.alloc(bool, paths.items.len);
    @memset(ticked, false);

    return .{
        .allocator = allocator,
        .function = try allocator.dupe(u8, function_name),
        .file = try allocator.dupe(u8, file),
        .paths = try paths.toOwnedSlice(allocator),
        .ticked = ticked,
    };
}

// One function declaration an enumeration walk found: its name, the line its own name token sits
// on, and which same-named declaration in this same file this is (zero for the first, one for the
// next, and so on, in the same order `buildOccurrence`'s own search counts them). Every string here
// is owned by whoever holds the slice `listDeclarations` returns, freed by `freeDeclarations`.
pub const Declaration = struct {
    name: []const u8,
    line: u32,
    occurrence: usize,

    // Whether anything outside this file can call it. A private function has no caller a run can
    // reach directly, so the only way it is ever exercised is through whatever public function of its
    // own file calls it.
    is_public: bool = false,
};

// The one way `listDeclarations` fails beyond running out of memory: the text handed in was not
// valid Zig at all. Unlike `build`, there is no "function not found" here, since this never looks
// for one function by name, only lists every one a file declares.
const ListError = std.mem.Allocator.Error || error{SourceDoesNotParse};

// The function whose body covers `line`, which is how a point recorded by an injector (a file and a
// line, and nothing else) is attributed to the function it fired in. The innermost match wins, so a
// point inside a nested function belongs to that one rather than to whatever holds it.
pub fn functionAtLine(allocator: std.mem.Allocator, source: [:0]const u8, line: u32) ListError!?Declaration {
    var tree = try Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) {
        return error.SourceDoesNotParse;
    }

    var seen_counts = std.StringHashMap(usize).init(allocator);
    defer seen_counts.deinit();

    var best: ?Declaration = null;
    var best_span: u32 = std.math.maxInt(u32);
    var index: u32 = 0;
    while (index < tree.nodes.len) : (index += 1) {
        const node: Ast.Node.Index = @enumFromInt(index);
        if (tree.nodeTag(node) != .fn_decl) {
            continue;
        }
        var proto_buffer: [1]Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&proto_buffer, node) orelse continue;
        const name_token = proto.name_token orelse continue;
        const name = tree.tokenSlice(name_token);

        const seen = try seen_counts.getOrPut(name);
        if (!seen.found_existing) {
            seen.value_ptr.* = 0;
        }
        const occurrence = seen.value_ptr.*;
        seen.value_ptr.* = occurrence + 1;

        const first = lineOf(tree, tree.firstToken(node));
        const last = lineOf(tree, tree.lastToken(node));
        if (line < first or line > last) {
            continue;
        }
        const span = last - first;
        if (span > best_span) {
            continue;
        }
        best_span = span;
        if (best) |previous| {
            allocator.free(previous.name);
        }
        best = .{
            .name = try allocator.dupe(u8, name),
            .line = lineOf(tree, name_token),
            .occurrence = occurrence,
        };
    }

    return best;
}

// Every `fn` declaration `source` holds, wherever it sits (top level, or nested in a container),
// in the order `tree.nodes` holds them. What a package's own enumeration reads to ask "does my own
// simulation exercise every function I declare", one file at a time, since which files a package owns
// and which it excludes (its own test files, its own harness entry points) is that package's own
// knowledge, not this framework's: `sim.zig`'s own header says the dependency runs one way.
pub fn listDeclarations(allocator: std.mem.Allocator, source: [:0]const u8) ListError![]const Declaration {
    var tree = try Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) {
        return error.SourceDoesNotParse;
    }

    var declarations: std.ArrayList(Declaration) = .empty;
    errdefer {
        for (declarations.items) |declaration| allocator.free(declaration.name);
        declarations.deinit(allocator);
    }

    // Counts, per name, how many declarations of it this walk has already found: what stamps each
    // one with the same `occurrence` number `buildOccurrence`'s own search would count up to before
    // finding it, so a caller can ask `buildOccurrence` for exactly the declaration this walk named.
    var seen_counts = std.StringHashMap(usize).init(allocator);
    defer seen_counts.deinit();

    var index: u32 = 0;
    while (index < tree.nodes.len) : (index += 1) {
        const node: Ast.Node.Index = @enumFromInt(index);
        if (tree.nodeTag(node) != .fn_decl) {
            continue;
        }
        var proto_buffer: [1]Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&proto_buffer, node) orelse continue;
        const name_token = proto.name_token orelse continue;
        const name = tree.tokenSlice(name_token);

        // A function returning `type` runs while the program is being compiled, so it has no run
        // for an annotation to be emitted in and no runtime path to prove. Read off the return
        // type itself rather than from a list of such functions kept somewhere else.
        if (proto.ast.return_type.unwrap()) |return_type| {
            if (tree.nodeTag(return_type) == .identifier and std.mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(return_type)), "type")) {
                continue;
            }
        }

        const seen = try seen_counts.getOrPut(name);
        if (!seen.found_existing) {
            seen.value_ptr.* = 0;
        }
        const occurrence = seen.value_ptr.*;
        seen.value_ptr.* = occurrence + 1;

        try declarations.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .line = lineOf(tree, name_token),
            .occurrence = occurrence,
            .is_public = proto.visib_token != null,
        });
    }

    return declarations.toOwnedSlice(allocator);
}

// Frees a slice `listDeclarations` returned, including every name string it owns.
pub fn freeDeclarations(allocator: std.mem.Allocator, declarations: []const Declaration) void {
    for (declarations) |declaration| {
        allocator.free(declaration.name);
    }
    allocator.free(declarations);
}

// Finds the `occurrence`-th `fn_decl` node named `function_name` anywhere in the tree (a top-level
// function, or one nested in a container: both are `fn_decl` nodes in a flat node array regardless
// of nesting) and returns its body block.
fn findFunctionBody(tree: Ast, function_name: []const u8, occurrence: usize) ?Ast.Node.Index {
    var index: u32 = 0;
    var seen: usize = 0;
    while (index < tree.nodes.len) : (index += 1) {
        const node: Ast.Node.Index = @enumFromInt(index);
        if (tree.nodeTag(node) != .fn_decl) {
            continue;
        }
        var proto_buffer: [1]Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&proto_buffer, node) orelse continue;
        const name_token = proto.name_token orelse continue;
        if (std.mem.eql(u8, tree.tokenSlice(name_token), function_name)) {
            if (seen == occurrence) {
                return tree.nodeData(node).node_and_node[1];
            }
            seen += 1;
        }
    }
    return null;
}

// The line a person reading the source would call this token's line: `Ast.tokenLocation` counts
// from zero, and every other place in this repository that names a line (`@src().line`, a plan's
// own `Point`) counts from one.
fn lineOf(tree: Ast, token: Ast.TokenIndex) u32 {
    return @intCast(tree.tokenLocation(0, token).line + 1);
}

// Every kind of branch `syntheticName` below can name, so a caller telling a synthesized name from
// a hand-written one reads the list rather than repeating it and going stale when one is added.
pub const synthesized_kinds = [_][]const u8{ "if:", "loop:", "switch:", "catch:", "orelse:", "and:", "or:", "try:" };

// Builds the synthesized name a branch gets when its own body carries no
// `if (an) annotate(log, "name", ...)`: stable across runs of `build` on the same source, and
// distinct from any real annotation name, since nothing produced by this repository's own
// `log.zig` names a path with a `:` in it the way this does.
fn syntheticName(allocator: std.mem.Allocator, kind: []const u8, line: u32, side: []const u8) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{d}:{s}", .{ kind, line, side });
}

// Whichever statements `body` holds, whether it is a `{ }` block or (for `if (an) annotate(...)`,
// the one statement this repository ever writes without braces) a single bare expression.
fn statementsOf(tree: Ast, body: Ast.Node.Index, buffer: *[2]Ast.Node.Index) []const Ast.Node.Index {
    return tree.blockStatements(buffer, body) orelse blk: {
        buffer[0] = body;
        break :blk buffer[0..1];
    };
}

// Whether `node` is exactly `if (an) annotate(<log>, <name-expr>, ...)`: the guard this repository
// writes at a call site rather than inside `annotate` itself, which makes it comptime-known and
// therefore
// never a path (item 5 of what this file is for). Returns every string literal found inside
// `<name-expr>`'s own token span, in source order: one for an ordinary call naming one path,
// several for a loop's `if (count == 0) "zero" else if (count == 1) "one" else "many"`-shaped
// classification, `null` where the shape does not match at all.
fn annotateNames(allocator: std.mem.Allocator, tree: Ast, node: Ast.Node.Index) std.mem.Allocator.Error!?[]const []const u8 {
    const if_full = tree.fullIf(node) orelse return null;
    if (if_full.ast.else_expr != .none) {
        return null;
    }
    const cond = if_full.ast.cond_expr;
    if (tree.nodeTag(cond) != .identifier) {
        return null;
    }
    if (!std.mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(cond)), "an")) {
        return null;
    }

    var call_buffer: [1]Ast.Node.Index = undefined;
    const call = tree.fullCall(&call_buffer, if_full.ast.then_expr) orelse return null;
    if (tree.nodeTag(call.ast.fn_expr) != .identifier) {
        return null;
    }
    if (!std.mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(call.ast.fn_expr)), "annotate")) {
        return null;
    }
    if (call.ast.params.len < 2) {
        return null;
    }

    const name_expr = call.ast.params[1];
    const first_token = tree.firstToken(name_expr);
    const last_token = tree.lastToken(name_expr);

    var names: std.ArrayList([]const u8) = .empty;
    errdefer names.deinit(allocator);
    var token = first_token;
    while (token <= last_token) : (token += 1) {
        if (tree.tokenTag(token) != .string_literal) {
            continue;
        }
        const raw = tree.tokenSlice(token);
        // Strips the surrounding quotes: every name this repository's own `annotate` call sites
        // pass is a plain identifier-shaped string with no escape sequence in it (confirmed by
        // reading every call site the annotation channel has), so nothing more than trimming one
        // character off each end is needed.
        try names.append(allocator, raw[1 .. raw.len - 1]);
    }
    if (names.items.len == 0) {
        names.deinit(allocator);
        return null;
    }
    return try names.toOwnedSlice(allocator);
}

// Looks for `if (an) annotate(...)` among `body`'s own statements (not any deeper: an annotation
// meant to name this branch sits directly in it, the same way every existing call site in
// an annotation sits directly in the block whose path it marks) and returns the one name found
// there, if the shape matches and names exactly one string.
fn singleAnnotateName(allocator: std.mem.Allocator, tree: Ast, body: Ast.Node.Index) std.mem.Allocator.Error!?[]const u8 {
    var buffer: [2]Ast.Node.Index = undefined;
    for (statementsOf(tree, body, &buffer)) |statement| {
        const names = (try annotateNames(allocator, tree, statement)) orelse continue;
        defer allocator.free(names);
        if (names.len != 1) {
            continue;
        }
        return try allocator.dupe(u8, names[0]);
    }
    return null;
}

// The name a branch gets: its own `annotate` call if it has exactly one, otherwise a synthesized
// name naming its kind, line and side.
fn nameFor(allocator: std.mem.Allocator, tree: Ast, body: Ast.Node.Index, kind: []const u8, line: u32, side: []const u8) std.mem.Allocator.Error![]const u8 {
    if (try singleAnnotateName(allocator, tree, body)) |found| {
        return found;
    }
    return syntheticName(allocator, kind, line, side);
}

// One branch, named and with its own answer to whether anything can ever say it ran.
//
// A branch written as a block can be marked: a line goes inside it. One written as an expression
// cannot, because there is nowhere in an expression to put a statement. A switch case that answers
// with a value, a fallback after `orelse`, and an `if` used as a value are all of that kind, and
// asking for a marker in one means asking for the expression to be rewritten as a block that does
// nothing but hold it.
fn pathFor(allocator: std.mem.Allocator, tree: Ast, body: Ast.Node.Index, kind: []const u8, line: u32, side: []const u8) std.mem.Allocator.Error!Path {
    if (try singleAnnotateName(allocator, tree, body)) |found| {
        return .{ .line = line, .name = found };
    }
    return .{
        .line = line,
        .name = try syntheticName(allocator, kind, line, side),
        .observable = canHoldAMarker(tree, body),
    };
}

// The not-taken side of an `if` that has no `else`.
//
// It is a real side: the condition did not hold and the code carried on past the `if`. Where the
// taken side leaves the function, carrying on is the only way the next statement runs, so the marker
// written there says the condition did not hold and nothing has to be added for it. Where the taken
// side carries on too, both sides meet at that same statement and it says nothing about which one
// happened, so nothing can mark it.
fn pathWithNoElse(
    allocator: std.mem.Allocator,
    tree: Ast,
    node: Ast.Node.Index,
    if_full: Ast.full.If,
    line: u32,
    function_name: []const u8,
) std.mem.Allocator.Error!Path {
    const name = try syntheticName(allocator, "if", line, "false");
    errdefer allocator.free(name);

    // Without a marker on the taken side there is nothing to count against, so nothing can say this
    // side ran.
    const taken = (try singleAnnotateName(allocator, tree, if_full.ast.then_expr)) orelse {
        return .{ .line = line, .name = name, .observable = false };
    };
    errdefer allocator.free(taken);

    // What says how often the `if` was reached at all. A function says so once per call; an `if`
    // inside a loop is reached once per turn of it, so there the loop's own line is the one to count
    // against and the function's would be short.
    const reached = (try enclosingIteration(allocator, tree, node)) orelse
        try std.fmt.allocPrint(allocator, "{s}:entered", .{function_name});
    return .{
        .line = line,
        .name = name,
        .not_taken = .{ .entered = reached, .taken = taken },
    };
}

// The iteration marker of the innermost loop this node sits inside, or null where it sits in none.
fn enclosingIteration(allocator: std.mem.Allocator, tree: Ast, node: Ast.Node.Index) std.mem.Allocator.Error!?[]const u8 {
    const first = tree.firstToken(node);
    const last = tree.lastToken(node);

    var innermost: ?Ast.Node.Index = null;
    var innermost_span: u32 = std.math.maxInt(u32);
    var index: u32 = 0;
    while (index < tree.nodes.len) : (index += 1) {
        const candidate: Ast.Node.Index = @enumFromInt(index);
        const body = loopBody(tree, candidate) orelse continue;
        const body_first = tree.firstToken(body);
        const body_last = tree.lastToken(body);
        if (first < body_first or last > body_last) {
            continue;
        }
        const span = body_last - body_first;
        if (span >= innermost_span) {
            continue;
        }
        innermost_span = span;
        innermost = body;
    }

    const body = innermost orelse return null;
    return firstStatementAnnotateName(allocator, tree, body);
}

// The body of a `while` or a `for`, or null for anything else.
fn loopBody(tree: Ast, node: Ast.Node.Index) ?Ast.Node.Index {
    if (tree.fullWhile(node)) |while_full| {
        return while_full.ast.then_expr;
    }
    if (tree.fullFor(node)) |for_full| {
        return for_full.ast.then_expr;
    }
    return null;
}

// Whether taking this branch means leaving: the body ends in a `return`, a `break` or a `continue`,
// so nothing after the `if` runs when it is taken.
fn takenSideLeaves(tree: Ast, body: Ast.Node.Index) bool {
    if (leaves(tree, body)) {
        return true;
    }
    var buffer: [2]Ast.Node.Index = undefined;
    const statements = tree.blockStatements(&buffer, body) orelse return false;
    if (statements.len == 0) {
        return false;
    }
    return leaves(tree, statements[statements.len - 1]);
}

fn leaves(tree: Ast, node: Ast.Node.Index) bool {
    return switch (tree.nodeTag(node)) {
        .@"return", .@"break", .@"continue" => true,
        else => isStop(tree, node),
    };
}

// Whether a marker can be written in this branch at all.
fn canHoldAMarker(tree: Ast, body: Ast.Node.Index) bool {
    var buffer: [2]Ast.Node.Index = undefined;
    return tree.blockStatements(&buffer, body) != null;
}

// One switch case's own label, read off its declared values: the source text of each, joined with
// `, `, or `"else"` for the catch-all every switch over an enum still needs a case list for.
fn caseLabel(allocator: std.mem.Allocator, tree: Ast, case: Ast.full.SwitchCase) std.mem.Allocator.Error![]const u8 {
    if (case.ast.values.len == 0) {
        return allocator.dupe(u8, "else");
    }
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(allocator);
    for (case.ast.values, 0..) |value, index| {
        if (index > 0) {
            try text.appendSlice(allocator, ", ");
        }
        try text.appendSlice(allocator, tree.getNodeSource(value));
    }
    return text.toOwnedSlice(allocator);
}

// One call a function's own body makes: the qualifier in front of it, if any, and the name called.
// `log_mod.info(...)` gives `log_mod` and `info`; `operation.run(...)` gives `operation` and `run`;
// a bare `helper(...)` gives no qualifier.
pub const Call = struct {
    qualifier: ?[]const u8,
    name: []const u8,
};

// Every call `function_name`'s own body makes, read from the tokens of that body. A call is
// `identifier (` or `identifier . identifier (`, so reading tokens finds one at any depth without
// following every expression kind the AST has.
pub fn listCalls(allocator: std.mem.Allocator, source: [:0]const u8, function_name: []const u8, occurrence: usize) (ListError || error{FunctionNotFound})![]const Call {
    var tree = try Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) {
        return error.SourceDoesNotParse;
    }

    const body = findFunctionBody(tree, function_name, occurrence) orelse return error.FunctionNotFound;

    var calls: std.ArrayList(Call) = .empty;
    errdefer {
        for (calls.items) |call| {
            if (call.qualifier) |qualifier| {
                allocator.free(qualifier);
            }
            allocator.free(call.name);
        }
        calls.deinit(allocator);
    }

    const tokens = tree.tokens.items(.tag);
    var index: usize = tree.firstToken(body);
    const last = tree.lastToken(body);

    while (index < last) : (index += 1) {
        if (tokens[index] != .identifier or tokens[index + 1] != .l_paren) {
            continue;
        }

        var qualifier: ?[]const u8 = null;
        if (index >= 2 and tokens[index - 1] == .period and tokens[index - 2] == .identifier) {
            qualifier = try allocator.dupe(u8, tree.tokenSlice(@intCast(index - 2)));
        }
        errdefer if (qualifier) |owned| allocator.free(owned);

        try calls.append(allocator, .{
            .qualifier = qualifier,
            .name = try allocator.dupe(u8, tree.tokenSlice(@intCast(index))),
        });
    }

    return calls.toOwnedSlice(allocator);
}

pub fn freeCalls(allocator: std.mem.Allocator, calls: []const Call) void {
    for (calls) |call| {
        if (call.qualifier) |qualifier| {
            allocator.free(qualifier);
        }
        allocator.free(call.name);
    }
    allocator.free(calls);
}

// One token range nothing inside is a path: an `if (an) annotate(...)` guard (the `if` it is
// written as, and any `if` expression choosing between names inside it, are the mechanism rather
// than branches of the code), or a function declared inside the one being walked, whose branches
// belong to its own checklist.
const Span = struct {
    first: Ast.TokenIndex,
    last: Ast.TokenIndex,
};

fn withinAny(spans: []const Span, first: Ast.TokenIndex, last: Ast.TokenIndex) bool {
    for (spans) |span| {
        if (first >= span.first and last <= span.last) {
            return true;
        }
    }
    return false;
}

// Every branch in `body`, wherever it is written. The walk is over the parser's own node array
// rather than over statements, because a branch is a branch whether it stands as a statement or
// sits inside an expression: an `if` inside a `catch` body, a `switch` that is the value of a
// `return`, an `orelse` block. Walking statements only was how `logExceptions`'s two sides went
// unreached while the run reported the function fully covered.
fn walkEveryBranch(allocator: std.mem.Allocator, tree: Ast, body: Ast.Node.Index, function_name: []const u8, paths: *std.ArrayList(Path)) std.mem.Allocator.Error!void {
    const body_first = tree.firstToken(body);
    const body_last = tree.lastToken(body);

    var skipped: std.ArrayList(Span) = .empty;
    defer skipped.deinit(allocator);

    var index: u32 = 0;
    while (index < tree.nodes.len) : (index += 1) {
        const node: Ast.Node.Index = @enumFromInt(index);
        const first = tree.firstToken(node);
        const last = tree.lastToken(node);
        if (first < body_first or last > body_last) {
            continue;
        }
        if (tree.nodeTag(node) == .fn_decl) {
            try skipped.append(allocator, .{ .first = first, .last = last });
            continue;
        }
        const names = (try annotateNames(allocator, tree, node)) orelse continue;
        allocator.free(names);
        try skipped.append(allocator, .{ .first = first, .last = last });
    }

    index = 0;
    while (index < tree.nodes.len) : (index += 1) {
        const node: Ast.Node.Index = @enumFromInt(index);
        const first = tree.firstToken(node);
        const last = tree.lastToken(node);
        if (first < body_first or last > body_last) {
            continue;
        }
        if (withinAny(skipped.items, first, last)) {
            continue;
        }

        if (tree.fullIf(node)) |if_full| {
            const line = lineOf(tree, if_full.ast.if_token);
            if (!isUnreachableBody(tree, if_full.ast.then_expr)) {
                try paths.append(allocator, try pathFor(allocator, tree, if_full.ast.then_expr, "if", line, "true"));
            }

            if (if_full.ast.else_expr.unwrap()) |else_expr| {
                if (!isUnreachableBody(tree, else_expr)) {
                    const at = lineOf(tree, tree.firstToken(else_expr));
                    try paths.append(allocator, try pathFor(allocator, tree, else_expr, "if", at, "false"));
                }
            } else {
                try paths.append(allocator, try pathWithNoElse(allocator, tree, node, if_full, line, function_name));
            }
            continue;
        }

        if (tree.fullSwitch(node)) |switch_full| {
            for (switch_full.ast.cases) |case_node| {
                const case_full = tree.fullSwitchCase(case_node) orelse continue;
                if (isUnreachableBody(tree, case_full.ast.target_expr)) {
                    continue;
                }
                const line = lineOf(tree, case_full.ast.arrow_token);
                const label = try caseLabel(allocator, tree, case_full);
                defer allocator.free(label);
                try paths.append(allocator, try pathFor(allocator, tree, case_full.ast.target_expr, "switch", line, label));
            }
            continue;
        }

        const loop_else: ?Ast.Node.OptionalIndex = if (tree.fullWhile(node)) |while_full|
            while_full.ast.else_expr
        else if (tree.fullFor(node)) |for_full|
            for_full.ast.else_expr
        else
            null;
        const loop_body = if (tree.fullWhile(node)) |while_full|
            while_full.ast.then_expr
        else if (tree.fullFor(node)) |for_full|
            for_full.ast.then_expr
        else
            null;
        if (loop_body) |loop_statements| {
            const line = lineOf(tree, tree.nodeMainToken(node));
            try appendLoopPaths(allocator, tree, .{
                .body = loop_statements,
                .line = line,
            }, paths);
            // A loop's own `else` runs when it finished without breaking, which no iteration count
            // can tell apart from breaking on the last one, so it is a path of its own.
            if (loop_else) |maybe_else| {
                if (maybe_else.unwrap()) |else_expr| {
                    if (isUnreachableBody(tree, else_expr)) {
                        continue;
                    }
                    const else_line = lineOf(tree, tree.firstToken(else_expr));
                    try paths.append(allocator, try pathFor(allocator, tree, else_expr, "loop", else_line, "completed"));
                }
            }
            continue;
        }

        // A short-circuit is a branch: the right side runs or it does not. Neither side can hold
        // an annotation, since there is nowhere in an expression to put a statement, so both are
        // named from the operator's own line, counted, and reported as unproven until the
        // condition is rewritten into an `if`.
        const short_circuit_kind: ?[]const u8 = switch (tree.nodeTag(node)) {
            .bool_and => "and",
            .bool_or => "or",
            else => null,
        };
        if (short_circuit_kind) |kind| {
            const line = lineOf(tree, tree.nodeMainToken(node));
            for ([_][]const u8{ "short-circuit", "evaluated" }) |side| {
                try paths.append(allocator, .{
                    .line = line,
                    .name = try syntheticName(allocator, kind, line, side),
                    .observable = false,
                });
            }
            continue;
        }

        // `try` is an early return out of the function when the call fails, which is a path
        // through it whether or not anything ever exercises the failure.
        if (tree.nodeTag(node) == .@"try") {
            const line = lineOf(tree, tree.nodeMainToken(node));
            try paths.append(allocator, .{
                .line = line,
                .name = try syntheticName(allocator, "try", line, "failed"),
                .observable = false,
            });
            continue;
        }

        // `catch` and `orelse` are branches wherever they appear, and they are always written as
        // expressions, so the statement walk never saw either. Two sides each: the fallback ran,
        // or the value came back and it did not.
        const fallback_kind: ?[]const u8 = switch (tree.nodeTag(node)) {
            .@"catch" => "catch",
            .@"orelse" => "orelse",
            else => null,
        };
        if (fallback_kind) |kind| {
            const line = lineOf(tree, tree.nodeMainToken(node));
            const fallback = tree.nodeData(node).node_and_node[1];
            if (isUnreachableBody(tree, fallback)) {
                continue;
            }
            try paths.append(allocator, try pathFor(allocator, tree, fallback, kind, line, "taken"));
            continue;
        }
    }
}

// Whether a branch's body is `unreachable`, either bare or as a block holding nothing else. Such a
// branch is an assertion that it cannot be taken, checked by the language itself: a run that takes
// it panics in a safe build. There is nothing for a test to reach, so it is not a path to prove,
// and writing one is how the code says a fallback cannot happen instead of a list saying so
// somewhere else.
fn isUnreachableBody(tree: Ast, node: Ast.Node.Index) bool {
    if (isStop(tree, node)) {
        return true;
    }
    var statements_buffer: [2]Ast.Node.Index = undefined;
    const statements = tree.blockStatements(&statements_buffer, node) orelse return false;
    return statements.len == 1 and isStop(tree, statements[0]);
}

// Whether one statement says the branch holding it cannot be taken: `unreachable`, a `@panic` that
// ends the run, or a `@compileError` that stops the build before there is a run at all. All three
// are the same claim, and a run can only reach one of them by ending.
fn isStop(tree: Ast, node: Ast.Node.Index) bool {
    if (tree.nodeTag(node) == .unreachable_literal) {
        return true;
    }
    if (tree.nodeTag(node) != .builtin_call_two and tree.nodeTag(node) != .builtin_call_two_comma) {
        return false;
    }
    const called = tree.tokenSlice(tree.nodeMainToken(node));
    return std.mem.eql(u8, called, "@panic") or std.mem.eql(u8, called, "@compileError");
}

// One loop the walk found, and what naming its path needs to know about it.
const LoopSite = struct {
    // The loop's body, whose first statement is where its annotation belongs.
    body: Ast.Node.Index,

    // The line the `while` or `for` keyword sits on, which the loop's path is reported at.
    line: u32,
};

// The one path a loop has: its body ran. The code says where that is, with a single annotation as
// the first statement of the body, and a run ticks the path when that name comes back.
//
// Only the body. Whether the loop went round once or many times, and whether it went round at all,
// are not paths here: a marker inside the body cannot say a loop was skipped, because a call that
// reached the loop and went round no times and a call that never reached the loop look the same
// from inside it. Counting one turn against many needed a second annotation before the loop to say
// where one traversal ended and the next began, which is a line per loop for a distinction nobody
// asked for.
//
// A loop with no annotation in its body gets a synthesized name instead, which no run can tick:
// that is how the report says the line has not been written yet.
fn appendLoopPaths(allocator: std.mem.Allocator, tree: Ast, site: LoopSite, paths: *std.ArrayList(Path)) std.mem.Allocator.Error!void {
    const iteration = try firstStatementAnnotateName(allocator, tree, site.body);
    defer if (iteration) |name| allocator.free(name);

    if (iteration == null) {
        try paths.append(allocator, .{
            .line = site.line,
            .name = try syntheticName(allocator, "loop", site.line, "body"),
            .observable = canHoldAMarker(tree, site.body),
        });
        return;
    }

    try paths.append(allocator, .{ .line = site.line, .name = try allocator.dupe(u8, iteration.?) });
}

// The name on the `if (an) annotate(...)` written as the first statement of `body`, which is how a
// loop body says it went round once more. Only the first statement counts, so an annotation deeper
// in the body, which a `continue` can skip, is never read as the iteration count.
fn firstStatementAnnotateName(allocator: std.mem.Allocator, tree: Ast, body: Ast.Node.Index) std.mem.Allocator.Error!?[]const u8 {
    var buffer: [2]Ast.Node.Index = undefined;
    const statements = statementsOf(tree, body, &buffer);
    if (statements.len == 0) {
        return null;
    }
    const names = (try annotateNames(allocator, tree, statements[0])) orelse return null;
    defer allocator.free(names);
    if (names.len != 1) {
        return null;
    }
    return try allocator.dupe(u8, names[0]);
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("coverage.test.zig");
}
