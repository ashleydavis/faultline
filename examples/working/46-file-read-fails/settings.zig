// A function that reads a file, with every path through it reachable because the run gives it a
// filesystem held in memory rather than the machine's own.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// What a setting says when the file will not give it up.
pub const fallback = "quiet";

// The file this module is written in terms of. The run reads the strings a module declares and
// tries them as arguments, so this is what gets a call as far as opening something.
pub const settings_path = "settings.txt";

// Reads the whole file, or says `fallback` when it cannot. Three paths: no such file, a file that
// opens but will not read, and a file that gives up its contents.
pub fn setting(log: Log, io: std.Io, path: []const u8, into: []u8) []const u8 {
    var file = std.Io.Dir.cwd().openFile(io, path, .{}) catch {
        if (an) annotate(log, "setting-no-such-file", "", .{});
        return fallback;
    };
    defer file.close(io);

    var reader = file.reader(io, &.{});
    const read = reader.interface.readSliceShort(into) catch {
        if (an) annotate(log, "setting-will-not-read", "", .{});
        return fallback;
    };
    if (read == 0) {
        if (an) annotate(log, "setting-empty", "", .{});
        return fallback;
    }
    return into[0..read];
}
