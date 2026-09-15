// Tests for the in-memory filesystem a simulation runs against.
//
// Every one of them drives it through `std.Io.Dir` and `std.Io.File` rather than through the entries
// directly, because what matters is that code written against the real filesystem works unchanged
// when this one is underneath it.

const std = @import("std");
const filesystem = @import("filesystem.zig");

// One installed filesystem, with the arena it holds everything in. The `Io` underneath is a real
// one, since the point of the layering is that everything this does not replace still works.
const Fake = struct {
    threaded: std.Io.Threaded,
    arena: std.heap.ArenaAllocator,
    room: std.Io.VTable,
    io: std.Io,

    fn create(self: *Fake, allocator: std.mem.Allocator) void {
        self.threaded = std.Io.Threaded.init(allocator, .{});
        self.arena = std.heap.ArenaAllocator.init(allocator);
        self.io = filesystem.install(self.threaded.io(), self.arena.allocator(), &self.room);
    }

    fn destroy(self: *Fake) void {
        filesystem.clear();
        self.arena.deinit();
        self.threaded.deinit();
    }
};

test "a file written is read back, and nothing reaches the disk" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "notes.txt", .data = "what it said" });

    const read = try cwd.readFileAlloc(fake.io, "notes.txt", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(read);
    try std.testing.expectEqualStrings("what it said", read);

    // The name is one no test would create on purpose, so a file of it on disk would mean this
    // wrote through to the real filesystem.
    var real = std.Io.Threaded.init(std.testing.allocator, .{});
    defer real.deinit();
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(real.io(), "notes.txt", .{}));
}

test "a file written twice keeps only what was written last" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "once.txt", .data = "the long first thing" });
    try cwd.writeFile(fake.io, .{ .sub_path = "once.txt", .data = "short" });

    const read = try cwd.readFileAlloc(fake.io, "once.txt", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(read);
    try std.testing.expectEqualStrings("short", read);
}

test "a file nothing wrote is not found" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    try std.testing.expectError(
        error.FileNotFound,
        std.Io.Dir.cwd().readFileAlloc(fake.io, "nowhere.txt", std.testing.allocator, .unlimited),
    );
}

test "a path is created a directory at a time, and a file under it is found" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(fake.io, "src/lib/deep");
    try cwd.writeFile(fake.io, .{ .sub_path = "src/lib/deep/thing.zig", .data = "const a = 1;" });

    const stat = try cwd.statFile(fake.io, "src/lib/deep/thing.zig", .{});
    try std.testing.expectEqual(@as(u64, 12), stat.size);
    try std.testing.expectEqual(std.Io.File.Kind.file, stat.kind);

    // Made on the way to the file, rather than only the directory that was asked for.
    const above = try cwd.statFile(fake.io, "src/lib", .{});
    try std.testing.expectEqual(std.Io.File.Kind.directory, above.kind);
}

test "a directory lists what is directly inside it and nothing below that" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "project/one.txt", .data = "" });
    try cwd.writeFile(fake.io, .{ .sub_path = "project/two.txt", .data = "" });
    try cwd.writeFile(fake.io, .{ .sub_path = "project/below/three.txt", .data = "" });

    var dir = try cwd.openDir(fake.io, "project", .{ .iterate = true });
    defer dir.close(fake.io);

    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |name| std.testing.allocator.free(name);
        names.deinit(std.testing.allocator);
    }

    var iterator = dir.iterate();
    while (try iterator.next(fake.io)) |entry| {
        try names.append(std.testing.allocator, try std.testing.allocator.dupe(u8, entry.name));
    }

    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    try std.testing.expectEqual(@as(usize, 3), names.items.len);
    try std.testing.expectEqualStrings("below", names.items[0]);
    try std.testing.expectEqualStrings("one.txt", names.items[1]);
    try std.testing.expectEqualStrings("two.txt", names.items[2]);
}

test "a deleted file is gone and a directory holding something refuses to go" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "held/inside.txt", .data = "" });

    try std.testing.expectError(error.DirNotEmpty, cwd.deleteDir(fake.io, "held"));

    try cwd.deleteFile(fake.io, "held/inside.txt");
    try std.testing.expectError(error.FileNotFound, cwd.statFile(fake.io, "held/inside.txt", .{}));

    try cwd.deleteDir(fake.io, "held");
    try std.testing.expectError(error.FileNotFound, cwd.statFile(fake.io, "held", .{}));
}

test "a rename moves a file and replaces whatever was in its way" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "written.tmp", .data = "the new contents" });
    try cwd.writeFile(fake.io, .{ .sub_path = "real.txt", .data = "the old contents" });

    try cwd.rename("written.tmp", cwd, "real.txt", fake.io);

    const read = try cwd.readFileAlloc(fake.io, "real.txt", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(read);
    try std.testing.expectEqualStrings("the new contents", read);
    try std.testing.expectError(error.FileNotFound, cwd.statFile(fake.io, "written.tmp", .{}));
}

test "clearing empties the tree, so one seed never sees what another wrote" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "from-the-last-seed.txt", .data = "" });
    filesystem.clear();

    try std.testing.expectError(error.FileNotFound, cwd.statFile(fake.io, "from-the-last-seed.txt", .{}));
}

test "an absolute path names itself rather than hanging off the working directory" {
    // A temporary directory is reached by an absolute path, and the two spellings have to be one
    // file: written through the absolute one and read back through it.
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "/tmp/made-up/thing.txt", .data = "held" });

    const read = try cwd.readFileAlloc(fake.io, "/tmp/made-up/thing.txt", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(read);
    try std.testing.expectEqualStrings("held", read);
}

test "a read-only directory refuses a new file, and allows one again when it is not" {
    // The code a run drives has a branch for a directory it cannot write into. Nothing reaches it
    // if permission is always given, which is why this filesystem honours permissions rather than
    // recording them.
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(fake.io, "locked");
    try cwd.setFilePermissions(fake.io, "locked", std.Io.File.Permissions.default_dir.setReadOnly(true), .{});

    try std.testing.expectError(
        error.AccessDenied,
        cwd.writeFile(fake.io, .{ .sub_path = "locked/new.txt", .data = "" }),
    );

    try cwd.setFilePermissions(fake.io, "locked", std.Io.File.Permissions.default_dir, .{});
    try cwd.writeFile(fake.io, .{ .sub_path = "locked/new.txt", .data = "" });
}

test "a read-only file refuses to be opened for writing" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "fixed.txt", .data = "what it says" });
    try cwd.setFilePermissions(fake.io, "fixed.txt", std.Io.File.Permissions.default_file.setReadOnly(true), .{});

    try std.testing.expectError(
        error.AccessDenied,
        cwd.writeFile(fake.io, .{ .sub_path = "fixed.txt", .data = "something else" }),
    );

    // Reading it is still allowed, which is the difference between read-only and not there.
    const read = try cwd.readFileAlloc(fake.io, "fixed.txt", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(read);
    try std.testing.expectEqualStrings("what it says", read);
}

test "a read-only directory refuses to have something deleted from it" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "kept/inside.txt", .data = "" });
    try cwd.setFilePermissions(fake.io, "kept", std.Io.File.Permissions.default_dir.setReadOnly(true), .{});

    try std.testing.expectError(error.AccessDenied, cwd.deleteFile(fake.io, "kept/inside.txt"));
}

test "a path below a file is refused as not a directory, not as missing" {
    // Code that has a branch for each only ever sees the second when a path below a file reads as
    // simply absent.
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "a-file", .data = "not a directory" });

    try std.testing.expectError(error.NotDir, cwd.statFile(fake.io, "a-file/below", .{}));
    try std.testing.expectError(error.NotDir, cwd.createDirPath(fake.io, "a-file/below"));
}

test "a file marked to fail opens and then refuses to be read" {
    // A real disk gives out part way through a read, and code written for that has a branch for it.
    // An in-memory read has nothing in it that can fail, so a scenario says which file should.
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "breaks.txt", .data = "some contents" });
    try filesystem.failReadsOf("breaks.txt");

    var file = try cwd.openFile(fake.io, "breaks.txt", .{});
    defer file.close(fake.io);

    var buffer: [8]u8 = undefined;
    var reader = file.reader(fake.io, &buffer);
    var into: [4]u8 = undefined;
    try std.testing.expectError(error.ReadFailed, reader.interface.readSliceShort(&into));
}

test "a file just written is recent, not ancient" {
    // Code asking whether a file is old enough to be abandoned compares it against the clock. A
    // fixed stamp makes every file look ancient, so the branch where a fresh one holds is never
    // reached.
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "fresh.lock", .data = "" });

    const stat = try cwd.statFile(fake.io, "fresh.lock", .{});
    const now = std.Io.Clock.Timestamp.now(fake.io, .real).raw;
    try std.testing.expect(now.nanoseconds - stat.mtime.nanoseconds < std.time.ns_per_s);
}

test "a file's timestamp can be set back, so a run can make one look abandoned" {
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "old.lock", .data = "" });

    var file = try cwd.openFile(fake.io, "old.lock", .{});
    defer file.close(fake.io);
    try file.setTimestamps(fake.io, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 1 } } });

    const stat = try cwd.statFile(fake.io, "old.lock", .{});
    try std.testing.expectEqual(@as(i96, 1), stat.mtime.nanoseconds);
}

test "a file marked unwritable refuses a write and refuses to be renamed over" {
    // The branch for a write that fails on its own cannot be reached by permissions alone, because
    // the lock file, the temporary file and the destination share one directory.
    var fake: Fake = undefined;
    fake.create(std.testing.allocator);
    defer fake.destroy();

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(fake.io, .{ .sub_path = "sealed.json", .data = "{}" });
    try cwd.writeFile(fake.io, .{ .sub_path = "next.tmp", .data = "{\"new\": true}" });
    try filesystem.failWritesOf("sealed.json");

    try std.testing.expectError(
        error.AccessDenied,
        cwd.writeFile(fake.io, .{ .sub_path = "sealed.json", .data = "{}" }),
    );
    try std.testing.expectError(error.AccessDenied, cwd.rename("next.tmp", cwd, "sealed.json", fake.io));
}
