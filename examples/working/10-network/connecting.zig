// A function that connects, with the failing side reached through the simulated network the run
// hands every call. Nothing here registers anything to make that happen.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// The address this module is written in terms of. The run reads the strings a module declares and
// tries them as arguments, so this is what gets the parse past its first branch.
pub const loopback_host = "127.0.0.1";

// Opens a connection and says whether it got one. Every call meets a network that refuses, so the
// failing side is reached without a scenario being written for it.
pub fn reachable(log: Log, io: std.Io, host: []const u8) bool {
    const address = std.Io.net.IpAddress.parse(host, 80) catch {
        if (an) annotate(log, "reachable-not-an-address", "", .{});
        return false;
    };
    var stream = address.connect(io, .{ .mode = .stream }) catch {
        if (an) annotate(log, "reachable-refused", "", .{});
        return false;
    };
    stream.close(io);
    return true;
}
