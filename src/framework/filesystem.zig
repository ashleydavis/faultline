// The filesystem a simulation runs against: a tree held in memory, with nothing on disk behind it.
//
// A run exercises a function hundreds of times per seed and sweeps many seeds, so code that writes a
// file pays for a syscall on every one of them, and leaves a directory behind when a call crashes
// halfway through. Neither belongs in a run whose point is to be fast and to leave the machine
// exactly as it found it.
//
// Layered over an `Io` the way `network.zig` layers the network: the entries that reach a disk are
// replaced and everything else is the real one, so the clock, the thread pool and the writers a
// caller already has keep working.
//
// The state is module-level for the reason `network.zig` gives: the `userdata` pointer in the `Io`
// belongs to whatever is underneath, and an entry here has to be able to reach both.

const std = @import("std");

const Dir = std.Io.Dir;
const File = std.Io.File;

// Where the tree's own memory comes from, set by `install`. An arena, so nothing here frees an
// individual entry and `clear` releases the lot in one go.
var allocator: std.mem.Allocator = undefined;

// The `Io` underneath, kept so an entry can hand a handle it does not own back to the real thing.
var underneath: std.Io = undefined;

// One file or directory. The whole tree is a flat list keyed by path rather than a structure of
// nodes, because every operation below arrives with a path already joined and none of them walks a
// tree a level at a time.
const Entry = struct {
    // Normalised: no leading "./", no trailing slash, and the root itself is the empty string.
    path: []const u8,
    kind: File.Kind,

    // Empty for a directory. Grown in place, so a file written twice keeps one allocation.
    contents: std.ArrayList(u8) = .empty,

    // When this entry was last written, read from the clock underneath rather than fixed. Code that
    // asks whether a file is recent compares it against that same clock, so a fixed value would make
    // every file look ancient: a lock file just taken would read as abandoned and be cleared, and
    // the branch where a lock holds could never be reached.
    mtime: std.Io.Timestamp = .{ .nanoseconds = 0 },

    // What a write, a create or a delete is allowed to do. Honoured rather than recorded, because
    // the code a run exercises has branches for a file it cannot write and a directory it cannot add
    // to, and nothing reaches them if permission is always given.
    permissions: File.Permissions = .default_file,
};

var entries: std.ArrayList(Entry) = .empty;

// One open handle. Kept by index, so the handle a caller holds is `first_handle` plus its position
// here and nothing has to be searched for.
const Open = struct {
    path: []const u8,
    kind: File.Kind,

    // Where the next streaming read or write lands. A positional one carries its own offset and
    // leaves this alone, which is what the two kinds mean.
    position: u64 = 0,

    // Closed handles are left in place rather than removed, because removing one would move every
    // handle after it and a caller is holding those numbers.
    open: bool = true,
};

var opens: std.ArrayList(Open) = .empty;

// Paths whose reads fail once the file is open. A real disk gives out part way through a read, and
// code written for that has a branch for it; an in-memory read has nothing in it that can fail, so
// a scenario says which file should. Named rather than drawn, so the same run does the same thing.
var failing_reads: std.ArrayList([]const u8) = .empty;

// Marks `path` so opening it works and reading it does not. Normalised the same way every other
// path here is, so a caller can pass whichever spelling its own code uses.
pub fn failReadsOf(path: []const u8) !void {
    try failing_reads.append(allocator, try joined("", path));
}

// Paths that cannot be written or replaced, whatever the directory holding them allows. A real
// filesystem does this with an immutable file or a read-only mount, and code with a branch for a
// write that fails on its own cannot reach it by permissions alone: the lock file, the temporary
// file and the destination all sit in one directory, so refusing that directory stops the first
// step rather than the one under test.
var failing_writes: std.ArrayList([]const u8) = .empty;

pub fn failWritesOf(path: []const u8) !void {
    try failing_writes.append(allocator, try joined("", path));
}

fn writesFail(path: []const u8) bool {
    for (failing_writes.items) |named| {
        if (std.mem.eql(u8, named, path)) {
            return true;
        }
    }
    return false;
}

fn readsFail(path: []const u8) bool {
    for (failing_reads.items) |named| {
        if (std.mem.eql(u8, named, path)) {
            return true;
        }
    }
    return false;
}

// Where this filesystem's handles start. Far above any descriptor a process is given, so a handle
// from here is never mistaken for a real one and a real one is never mistaken for a handle from
// here. Anything outside the range is passed to the `Io` underneath untouched, which is what keeps
// stdout, stderr and a pipe working while the tree is in memory.
const first_handle: Dir.Handle = 1 << 29;

// What `Dir.cwd()` returns. Code under test reaches the tree through it, so it is the root here.
const cwd_handle: Dir.Handle = if (@hasDecl(std.posix.AT, "FDCWD")) std.posix.AT.FDCWD else -100;

// Layers the in-memory filesystem over `io`. The vtable is written into `room` rather than returned
// by value for the reason `network.zig` gives: an `Io` holds a pointer to its vtable, and one on
// this function's stack would be gone by the time it is read.
//
// `arena` owns everything the tree holds. `clear` empties the tree without touching the arena, so a
// caller sweeping seeds resets between them and frees once at the end.
pub fn install(io: std.Io, arena: std.mem.Allocator, room: *std.Io.VTable) std.Io {
    allocator = arena;
    underneath = io;
    entries = .empty;
    opens = .empty;
    failing_reads = .empty;
    failing_writes = .empty;

    room.* = io.vtable.*;

    room.dirCreateDirPath = createDirPath;
    room.dirOpenDir = openDir;
    room.dirClose = closeDirs;
    room.dirStat = statDir;
    room.dirStatFile = statFile;
    room.dirAccess = access;
    room.dirCreateFile = createFile;
    room.dirOpenFile = openFile;
    room.dirRead = readDir;
    room.dirDeleteFile = deleteFile;
    room.dirDeleteDir = deleteDir;
    room.dirRename = rename;

    room.fileClose = closeFiles;
    room.fileStat = statOpenFile;
    room.fileLength = lengthOf;
    room.fileReadPositional = readPositional;
    room.fileWritePositional = writePositional;
    room.fileSetLength = setLength;
    room.fileSync = sync;
    room.dirSetPermissions = setDirPermissions;
    room.dirSetFilePermissions = setFilePermissionsByPath;
    room.fileSetPermissions = setFilePermissions;
    room.fileSetTimestamps = setTimestamps;
    room.fileIsTty = isTty;
    room.fileSeekTo = seekTo;
    room.fileSeekBy = seekBy;

    // Reading and writing a stream do not have entries of their own: they arrive as an `Operation`
    // through `operate`, which is also how a socket and a device are reached. Only the two file
    // ones are answered here and everything else goes underneath.
    room.operate = operate;

    return .{ .userdata = io.userdata, .vtable = room };
}

// Empties the tree and forgets every handle. The arena keeps the memory, so a run sweeping seeds
// starts each one from nothing without paying to free entry by entry.
pub fn clear() void {
    entries = .empty;
    opens = .empty;
    failing_reads = .empty;
    failing_writes = .empty;
}

// Whether this handle is one of ours. A directory a caller opened here, or the working directory,
// which is the root of the tree.
fn ours(handle: Dir.Handle) bool {
    return handle == cwd_handle or handle >= first_handle;
}

// The path a directory handle stands for, with the root spelled as the empty string.
fn directoryPath(dir: Dir) ?[]const u8 {
    if (dir.handle == cwd_handle) {
        return "";
    }
    const at = handleIndex(dir.handle) orelse return null;
    if (!opens.items[at].open) {
        return null;
    }
    return opens.items[at].path;
}

fn handleIndex(handle: Dir.Handle) ?usize {
    if (handle < first_handle) {
        return null;
    }
    const at: usize = @intCast(handle - first_handle);
    if (at >= opens.items.len) {
        return null;
    }
    return at;
}

// `parent` and `name` joined and tidied: "." and a leading "./" go, and so does a trailing slash.
// Everything below keys on the result, so two spellings of one path have to come out the same.
fn joined(parent: []const u8, name: []const u8) ![]const u8 {
    var tidy = name;
    while (std.mem.startsWith(u8, tidy, "./")) {
        tidy = tidy[2..];
    }
    while (tidy.len > 1 and std.mem.endsWith(u8, tidy, "/")) {
        tidy = tidy[0 .. tidy.len - 1];
    }
    if (std.mem.eql(u8, tidy, ".")) {
        tidy = "";
    }

    // An absolute path names itself. A run's code reaches a temporary directory that way, and
    // hanging it off the working directory would put two spellings of one file in the tree.
    if (std.mem.startsWith(u8, tidy, "/")) {
        return allocator.dupe(u8, tidy[1..]);
    }
    if (parent.len == 0) {
        return allocator.dupe(u8, tidy);
    }
    if (tidy.len == 0) {
        return allocator.dupe(u8, parent);
    }
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ parent, tidy });
}

// Whether something along the way to `path` is a file rather than a directory, which is what a real
// filesystem refuses with `NotDir`. Without this check a path below a file reads as simply missing,
// and code with a branch for one and a branch for the other only ever sees the second.
fn throughAFile(path: []const u8) bool {
    var at: usize = 0;
    while (std.mem.indexOfScalarPos(u8, path, at, '/')) |slash| {
        if (find(path[0..slash])) |above| {
            if (above.kind != .directory) {
                return true;
            }
        }
        at = slash + 1;
    }
    return false;
}

// The directory a path sits directly inside, or null when it sits at the root.
fn holdingDirectory(path: []const u8) ?*Entry {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return null;
    return find(path[0..slash]);
}

fn find(path: []const u8) ?*Entry {
    for (entries.items) |*entry| {
        if (std.mem.eql(u8, entry.path, path)) {
            return entry;
        }
    }
    return null;
}

// Whether `path` sits directly inside `parent`, which is what a listing asks and what a delete of a
// non-empty directory has to refuse.
fn directlyInside(parent: []const u8, path: []const u8) bool {
    if (path.len == 0) {
        return false;
    }
    if (parent.len == 0) {
        return std.mem.indexOfScalar(u8, path, '/') == null;
    }
    if (!std.mem.startsWith(u8, path, parent)) {
        return false;
    }
    if (path.len <= parent.len or path[parent.len] != '/') {
        return false;
    }
    return std.mem.indexOfScalar(u8, path[parent.len + 1 ..], '/') == null;
}

// Every directory above `path`, made if it is not there. A path is created a level at a time so a
// listing of a parent finds the child, which a flat list holding only the leaf would not.
fn makeParents(path: []const u8) !void {
    var at: usize = 0;
    while (std.mem.indexOfScalarPos(u8, path, at, '/')) |slash| {
        const above = path[0..slash];
        if (find(above) == null) {
            try entries.append(allocator, .{ .path = try allocator.dupe(u8, above), .kind = .directory });
        }
        at = slash + 1;
    }
}

fn openHandle(path: []const u8, kind: File.Kind) !Dir.Handle {
    try opens.append(allocator, .{ .path = path, .kind = kind });
    return first_handle + @as(Dir.Handle, @intCast(opens.items.len - 1));
}

fn createDirPath(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    permissions: Dir.Permissions,
) Dir.CreateDirPathError!Dir.CreatePathStatus {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirCreateDirPath(userdata, dir, sub_path, permissions);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.NotDir;
    }
    if (find(path)) |existing| {
        if (existing.kind != .directory) {
            return error.NotDir;
        }
        return .existed;
    }
    makeParents(path) catch return error.SystemResources;
    entries.append(allocator, .{ .path = path, .kind = .directory }) catch return error.SystemResources;
    return .created;
}

fn openDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.OpenOptions) Dir.OpenError!Dir {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirOpenDir(userdata, dir, sub_path, options);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.NotDir;
    }

    // The root is always there. Nothing creates it, and a run that opens the working directory
    // before writing anything would otherwise be told it does not exist.
    if (path.len != 0) {
        const entry = find(path) orelse return error.FileNotFound;
        if (entry.kind != .directory) {
            return error.NotDir;
        }
    }
    const handle = openHandle(path, .directory) catch return error.SystemResources;
    return .{ .handle = handle };
}

fn closeDirs(userdata: ?*anyopaque, closing: []const Dir) void {
    for (closing) |dir| {
        if (!ours(dir.handle)) {
            underneath.vtable.dirClose(userdata, &.{dir});
            continue;
        }
        if (handleIndex(dir.handle)) |at| {
            opens.items[at].open = false;
        }
    }
}

fn statDir(userdata: ?*anyopaque, dir: Dir) Dir.StatError!Dir.Stat {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirStat(userdata, dir);
    }
    return .{
        .inode = 0,
        .nlink = 1,
        .size = 0,
        .permissions = .default_dir,
        .kind = .directory,
        .atime = null,
        .mtime = .{ .nanoseconds = 0 },
        .ctime = .{ .nanoseconds = 0 },
        .block_size = 4096,
    };
}

fn statOf(entry: *const Entry) File.Stat {
    return .{
        .inode = 0,
        .nlink = 1,
        .size = entry.contents.items.len,
        .permissions = if (entry.kind == .directory) .default_dir else .default_file,
        .kind = entry.kind,
        .atime = null,
        .mtime = entry.mtime,
        .ctime = entry.mtime,
        .block_size = 4096,
    };
}

fn statFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.StatFileOptions,
) Dir.StatFileError!File.Stat {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirStatFile(userdata, dir, sub_path, options);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.NotDir;
    }
    const entry = find(path) orelse return error.FileNotFound;
    return statOf(entry);
}

fn access(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.AccessOptions) Dir.AccessError!void {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirAccess(userdata, dir, sub_path, options);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.FileNotFound; // NotDir is not in this error set, and a path below a file is not there either.
    }
    if (find(path) == null) {
        return error.FileNotFound;
    }
}

fn createFile(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    options: Dir.CreateFileOptions,
) File.OpenError!File {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirCreateFile(userdata, dir, sub_path, options);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.NotDir;
    }

    if (find(path)) |existing| {
        if (existing.kind == .directory) {
            return error.IsDir;
        }
        if (options.exclusive) {
            return error.PathAlreadyExists;
        }
        if (existing.permissions.readOnly() or writesFail(path)) {
            return error.AccessDenied;
        }
        if (options.truncate) {
            existing.contents.clearRetainingCapacity();
        }
    } else {
        // A new file goes inside its directory, so that directory has to allow being added to.
        if (holdingDirectory(path)) |above| {
            if (above.permissions.readOnly()) {
                return error.AccessDenied;
            }
        }
        makeParents(path) catch return error.SystemResources;
        entries.append(allocator, .{ .path = path, .kind = .file, .mtime = now() }) catch return error.SystemResources;
    }

    const handle = openHandle(path, .file) catch return error.SystemResources;
    return .{ .handle = handle, .flags = .{ .nonblocking = false } };
}

fn openFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8, options: Dir.OpenFileOptions) File.OpenError!File {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirOpenFile(userdata, dir, sub_path, options);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.NotDir;
    }
    const entry = find(path) orelse return error.FileNotFound;
    if (entry.kind == .directory) {
        return error.IsDir;
    }
    const handle = openHandle(path, .file) catch return error.SystemResources;
    return .{ .handle = handle, .flags = .{ .nonblocking = false } };
}

fn readDir(userdata: ?*anyopaque, reader: *Dir.Reader, into: []Dir.Entry) Dir.Reader.Error!usize {
    if (!ours(reader.dir.handle)) {
        return underneath.vtable.dirRead(userdata, reader, into);
    }
    if (reader.state == .reset) {
        reader.index = 0;
        reader.state = .reading;
    }
    const parent = directoryPath(reader.dir) orelse return 0;

    // `index` counts entries already handed over rather than a position in `buffer`, which this
    // filesystem does not use: the names it returns point into the tree, which owns them.
    var seen: usize = 0;
    var written: usize = 0;
    for (entries.items) |entry| {
        if (!directlyInside(parent, entry.path)) {
            continue;
        }
        seen += 1;
        if (seen <= reader.index) {
            continue;
        }
        if (written == into.len) {
            break;
        }
        const slash = std.mem.lastIndexOfScalar(u8, entry.path, '/');
        const name = if (slash) |at| entry.path[at + 1 ..] else entry.path;
        into[written] = .{ .name = name, .kind = entry.kind, .inode = 0 };
        written += 1;
        reader.index += 1;
    }

    // `Reader.next` loops until this says so rather than stopping on an empty read, so a listing
    // that just returned nothing would spin forever without it.
    if (written < into.len) {
        reader.state = .finished;
    }
    return written;
}

fn deleteFile(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteFileError!void {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirDeleteFile(userdata, dir, sub_path);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.NotDir;
    }
    for (entries.items, 0..) |entry, at| {
        if (!std.mem.eql(u8, entry.path, path)) {
            continue;
        }
        if (entry.kind == .directory) {
            return error.IsDir;
        }
        if (holdingDirectory(path)) |above| {
            if (above.permissions.readOnly()) {
                return error.AccessDenied;
            }
        }
        _ = entries.orderedRemove(at);
        return;
    }
    return error.FileNotFound;
}

fn deleteDir(userdata: ?*anyopaque, dir: Dir, sub_path: []const u8) Dir.DeleteDirError!void {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirDeleteDir(userdata, dir, sub_path);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.NotDir;
    }

    for (entries.items) |entry| {
        if (directlyInside(path, entry.path)) {
            return error.DirNotEmpty;
        }
    }
    for (entries.items, 0..) |entry, at| {
        if (!std.mem.eql(u8, entry.path, path)) {
            continue;
        }
        if (entry.kind != .directory) {
            return error.NotDir;
        }
        _ = entries.orderedRemove(at);
        return;
    }
    return error.FileNotFound;
}

fn rename(
    userdata: ?*anyopaque,
    old_dir: Dir,
    old_sub_path: []const u8,
    new_dir: Dir,
    new_sub_path: []const u8,
) Dir.RenameError!void {
    if (!ours(old_dir.handle) or !ours(new_dir.handle)) {
        return underneath.vtable.dirRename(userdata, old_dir, old_sub_path, new_dir, new_sub_path);
    }
    const old_parent = directoryPath(old_dir) orelse return error.FileNotFound;
    const new_parent = directoryPath(new_dir) orelse return error.FileNotFound;
    const from = joined(old_parent, old_sub_path) catch return error.SystemResources;
    const to = joined(new_parent, new_sub_path) catch return error.SystemResources;

    const moving = find(from) orelse return error.FileNotFound;
    if (writesFail(to)) {
        return error.AccessDenied;
    }
    if (holdingDirectory(to)) |above| {
        if (above.permissions.readOnly()) {
            return error.AccessDenied;
        }
    }

    // A rename over something replaces it, which is what makes an atomic write atomic: the writer
    // writes a temporary file and renames it onto the real one.
    for (entries.items, 0..) |entry, at| {
        if (std.mem.eql(u8, entry.path, to)) {
            _ = entries.orderedRemove(at);
            break;
        }
    }
    makeParents(to) catch return error.SystemResources;
    moving.path = to;
}

fn closeFiles(userdata: ?*anyopaque, closing: []const File) void {
    for (closing) |file| {
        if (!ours(file.handle)) {
            underneath.vtable.fileClose(userdata, &.{file});
            continue;
        }
        if (handleIndex(file.handle)) |at| {
            opens.items[at].open = false;
        }
    }
}

// The entry an open file handle stands for, or null when the handle is closed or its file has since
// been deleted.
fn openEntry(file: File) ?*Entry {
    const at = handleIndex(file.handle) orelse return null;
    if (!opens.items[at].open) {
        return null;
    }
    return find(opens.items[at].path);
}

fn statOpenFile(userdata: ?*anyopaque, file: File) File.StatError!File.Stat {
    if (!ours(file.handle)) {
        return underneath.vtable.fileStat(userdata, file);
    }
    const entry = openEntry(file) orelse return error.Unexpected;
    return statOf(entry);
}

fn lengthOf(userdata: ?*anyopaque, file: File) File.LengthError!u64 {
    if (!ours(file.handle)) {
        return underneath.vtable.fileLength(userdata, file);
    }
    const entry = openEntry(file) orelse return error.Unexpected;
    return entry.contents.items.len;
}

fn readPositional(userdata: ?*anyopaque, file: File, data: []const []u8, offset: u64) File.ReadPositionalError!usize {
    if (!ours(file.handle)) {
        return underneath.vtable.fileReadPositional(userdata, file, data, offset);
    }
    const entry = openEntry(file) orelse return error.Unexpected;
    if (readsFail(entry.path)) {
        return error.InputOutput;
    }
    const contents = entry.contents.items;

    // Nothing copied is how this error set says end of file: it has no end-of-stream in it, and a
    // reader that gets zero bytes back stops.
    var at: usize = @intCast(offset);
    var copied: usize = 0;
    for (data) |into| {
        if (at >= contents.len) {
            break;
        }
        const taking = @min(into.len, contents.len - at);
        @memcpy(into[0..taking], contents[at .. at + taking]);
        at += taking;
        copied += taking;
    }
    return copied;
}

fn writePositional(
    userdata: ?*anyopaque,
    file: File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
    offset: u64,
) File.WritePositionalError!usize {
    if (!ours(file.handle)) {
        return underneath.vtable.fileWritePositional(userdata, file, header, data, splat, offset);
    }
    const entry = openEntry(file) orelse return error.Unexpected;

    var at: usize = @intCast(offset);
    var written: usize = 0;
    put(entry, at, header) catch return error.NoSpaceLeft;
    at += header.len;
    written += header.len;

    // The last run of `data` is repeated `splat` times, which is how a writer sends a fill without
    // building it. Everything before it goes once.
    for (data, 0..) |piece, index| {
        const times = if (index == data.len - 1) splat else 1;
        var again: usize = 0;
        while (again < times) : (again += 1) {
            put(entry, at, piece) catch return error.NoSpaceLeft;
            at += piece.len;
            written += piece.len;
        }
    }
    return written;
}

// The moment now, from the clock underneath. The filesystem is in memory but the clock is the real
// one, and a file's age is only ever compared against that.
fn now() std.Io.Timestamp {
    return std.Io.Clock.Timestamp.now(.{ .userdata = underneath.userdata, .vtable = underneath.vtable }, .real).raw;
}

// Writes `bytes` into `entry` at `at`, growing it with zeros first when the write starts past the
// end. A positional write is allowed to leave a hole, and a file shorter than its own offset would
// otherwise read back as the wrong length.
fn put(entry: *Entry, at: usize, bytes: []const u8) !void {
    entry.mtime = now();
    if (bytes.len == 0) {
        return;
    }
    if (entry.contents.items.len < at + bytes.len) {
        const was = entry.contents.items.len;
        try entry.contents.resize(allocator, at + bytes.len);
        if (was < at) {
            @memset(entry.contents.items[was..at], 0);
        }
    }
    @memcpy(entry.contents.items[at .. at + bytes.len], bytes);
}

fn setLength(userdata: ?*anyopaque, file: File, length: u64) File.SetLengthError!void {
    if (!ours(file.handle)) {
        return underneath.vtable.fileSetLength(userdata, file, length);
    }
    const entry = openEntry(file) orelse return error.Unexpected;
    const want: usize = @intCast(length);
    const was = entry.contents.items.len;
    entry.contents.resize(allocator, want) catch return error.FileTooBig;
    if (was < want) {
        @memset(entry.contents.items[was..want], 0);
    }
}

fn sync(userdata: ?*anyopaque, file: File) File.SyncError!void {
    if (!ours(file.handle)) {
        return underneath.vtable.fileSync(userdata, file);
    }

    // Nothing is behind this filesystem, so there is nothing for a flush to push out to.
}

fn isTty(userdata: ?*anyopaque, file: File) std.Io.Cancelable!bool {
    if (!ours(file.handle)) {
        return underneath.vtable.fileIsTty(userdata, file);
    }
    return false;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("filesystem.test.zig");
}

fn seekTo(userdata: ?*anyopaque, file: File, absolute_offset: u64) File.SeekError!void {
    if (!ours(file.handle)) {
        return underneath.vtable.fileSeekTo(userdata, file, absolute_offset);
    }
    const at = handleIndex(file.handle) orelse return error.Unseekable;
    opens.items[at].position = absolute_offset;
}

fn seekBy(userdata: ?*anyopaque, file: File, relative_offset: i64) File.SeekError!void {
    if (!ours(file.handle)) {
        return underneath.vtable.fileSeekBy(userdata, file, relative_offset);
    }
    const at = handleIndex(file.handle) orelse return error.Unseekable;
    const was: i64 = @intCast(opens.items[at].position);
    const moved = was + relative_offset;
    if (moved < 0) {
        return error.Unseekable;
    }
    opens.items[at].position = @intCast(moved);
}

// A streaming read or write, which is what `writeFile` and a `File.Reader` use. Both carry no
// offset, so the position on the handle is what says where they land.
fn operate(userdata: ?*anyopaque, operation: std.Io.Operation) std.Io.Cancelable!std.Io.Operation.Result {
    switch (operation) {
        .file_write_streaming => |asked| {
            if (!ours(asked.file.handle)) {
                return underneath.vtable.operate(userdata, operation);
            }
            const at = handleIndex(asked.file.handle) orelse
                return .{ .file_write_streaming = error.NotOpenForWriting };
            const entry = openEntry(asked.file) orelse
                return .{ .file_write_streaming = error.NotOpenForWriting };

            var position: usize = @intCast(opens.items[at].position);
            var written: usize = 0;
            put(entry, position, asked.header) catch
                return .{ .file_write_streaming = error.NoSpaceLeft };
            position += asked.header.len;
            written += asked.header.len;

            for (asked.data, 0..) |piece, index| {
                const times = if (index == asked.data.len - 1) asked.splat else 1;
                var again: usize = 0;
                while (again < times) : (again += 1) {
                    put(entry, position, piece) catch
                        return .{ .file_write_streaming = error.NoSpaceLeft };
                    position += piece.len;
                    written += piece.len;
                }
            }
            opens.items[at].position = position;
            return .{ .file_write_streaming = written };
        },
        .file_read_streaming => |asked| {
            if (!ours(asked.file.handle)) {
                return underneath.vtable.operate(userdata, operation);
            }
            const at = handleIndex(asked.file.handle) orelse
                return .{ .file_read_streaming = error.NotOpenForReading };
            const entry = openEntry(asked.file) orelse
                return .{ .file_read_streaming = error.NotOpenForReading };
            if (readsFail(entry.path)) {
                return .{ .file_read_streaming = error.InputOutput };
            }

            const contents = entry.contents.items;
            var position: usize = @intCast(opens.items[at].position);
            if (position >= contents.len) {
                return .{ .file_read_streaming = error.EndOfStream };
            }

            var copied: usize = 0;
            for (asked.data) |into| {
                if (position >= contents.len) {
                    break;
                }
                const taking = @min(into.len, contents.len - position);
                @memcpy(into[0..taking], contents[position .. position + taking]);
                position += taking;
                copied += taking;
            }
            opens.items[at].position = position;
            return .{ .file_read_streaming = copied };
        },
        else => {
            return underneath.vtable.operate(userdata, operation);
        },
    }
}

fn setDirPermissions(userdata: ?*anyopaque, dir: Dir, new_permissions: Dir.Permissions) Dir.SetPermissionsError!void {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirSetPermissions(userdata, dir, new_permissions);
    }
    const path = directoryPath(dir) orelse return error.FileNotFound;
    const entry = find(path) orelse return error.FileNotFound;
    entry.permissions = new_permissions;
}

fn setFilePermissionsByPath(
    userdata: ?*anyopaque,
    dir: Dir,
    sub_path: []const u8,
    new_permissions: File.Permissions,
    options: Dir.SetFilePermissionsOptions,
) Dir.SetFilePermissionsError!void {
    if (!ours(dir.handle)) {
        return underneath.vtable.dirSetFilePermissions(userdata, dir, sub_path, new_permissions, options);
    }
    const parent = directoryPath(dir) orelse return error.FileNotFound;
    const path = joined(parent, sub_path) catch return error.SystemResources;
    if (throughAFile(path)) {
        return error.FileNotFound; // NotDir is not in this error set, and a path below a file is not there either.
    }
    const entry = find(path) orelse return error.FileNotFound;
    entry.permissions = new_permissions;
}

fn setFilePermissions(userdata: ?*anyopaque, file: File, new_permissions: File.Permissions) File.SetPermissionsError!void {
    if (!ours(file.handle)) {
        return underneath.vtable.fileSetPermissions(userdata, file, new_permissions);
    }
    const entry = openEntry(file) orelse return error.FileNotFound;
    entry.permissions = new_permissions;
}

fn setTimestamps(userdata: ?*anyopaque, file: File, options: File.SetTimestampsOptions) File.SetTimestampsError!void {
    if (!ours(file.handle)) {
        return underneath.vtable.fileSetTimestamps(userdata, file, options);
    }
    const entry = openEntry(file) orelse return error.Unexpected; // The only error this set holds for a handle whose file has gone.
    switch (options.modify_timestamp) {
        .unchanged => {},
        .now => entry.mtime = now(),
        .new => |stamp| entry.mtime = stamp,
    }

    // The access time is not kept: nothing here reads it back, and `statOf` reports it as absent
    // rather than inventing one.
}
