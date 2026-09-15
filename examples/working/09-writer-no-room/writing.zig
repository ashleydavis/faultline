// A function that writes, with the failing side reached by the writer the run supplies having
// almost no room.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Writes a line, and says so when it did not fit.
pub fn writeLine(log: Log, writer: *std.Io.Writer, text: []const u8) bool {
    writer.writeAll(text) catch {
        if (an) annotate(log, "writeLine-no-room", "", .{});
        return false;
    };
    return true;
}
