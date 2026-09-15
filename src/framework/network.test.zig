// Tests for the simulated network: what it refuses, and that it leaves everything else alone.

const std = @import("std");
const network = @import("network.zig");

test "every connection is refused, in the order the failures rotate" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();

    var room: std.Io.VTable = undefined;
    const io = network.simulated(threaded.io(), &room);

    const address = std.Io.net.IpAddress{ .ip4 = .loopback(80) };

    // The rotation is over a list the file declares, so a run of attempts meets more than one way
    // of failing rather than the same one forever. Which one comes first depends on how many
    // attempts have already been made in this process, so what is asserted is that they differ.
    var seen: [8]anyerror = undefined;
    for (&seen) |*slot| {
        slot.* = if (address.connect(io, .{ .mode = .stream })) |_| error.Connected else |err| err;
    }

    for (seen) |err| {
        try std.testing.expect(err != error.Connected);
    }

    var differed = false;
    for (seen[1..]) |err| {
        if (err != seen[0]) {
            differed = true;
        }
    }
    try std.testing.expect(differed);
}

test "no name resolves" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();

    var room: std.Io.VTable = undefined;
    const io = network.simulated(threaded.io(), &room);

    var storage: [4]std.Io.net.HostName.LookupResult = undefined;
    var queue: std.Io.Queue(std.Io.net.HostName.LookupResult) = .init(&storage);

    const name = std.Io.net.HostName.init("example.invalid") catch unreachable;
    if (io.vtable.netLookup(io.userdata, name, &queue, .{ .port = 80 })) |_| {
        return error.NameResolved;
    } else |err| {
        // Any of the lookup failures is the right answer; the point is that none resolves.
        try std.testing.expect(err == error.UnknownHostName or
            err == error.NameServerFailure or
            err == error.NoAddressReturned);
    }
}

test "everything that is not the network is left as it was" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const real = threaded.io();

    var room: std.Io.VTable = undefined;
    const simulated = network.simulated(real, &room);

    // The userdata is the same implementation, and the calls that do not reach a machine are the
    // real ones: only what would go out over a network is replaced.
    try std.testing.expectEqual(real.userdata, simulated.userdata);
    try std.testing.expectEqual(real.vtable.now, simulated.vtable.now);
    try std.testing.expect(real.vtable.netConnectIp != simulated.vtable.netConnectIp);
}
