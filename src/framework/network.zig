// The network a simulated run gets. No name is looked up, no socket is opened, and nothing reaches
// a machine: every attempt fails in one of the ways a real network fails, and the failures rotate
// so a function called many times sees each one.
//
// This is what makes a function that fetches over the network testable without anybody writing
// anything for it. Handed the real network, the run would dial whatever address the code under test
// names, wait for a stranger's server, and produce a different answer on every machine and every
// day. It did exactly that until 2026-09-10: a run reached the geocoding API for real, each call
// sat until the stall limit, every stall restarted the child, and the whole run made no progress
// while printing nothing.
//
// Nothing here names a package's own types. What a request means, and what a failed one costs, are
// entirely the calling package's own.

const std = @import("std");
const net = std.Io.net;

// Which failure the next attempt gets. A container-level variable rather than state behind the
// `userdata` pointer, because the vtable entries below sit in an `Io` whose userdata belongs to the
// implementation they are layered over, and there is nowhere else to put it. Each child process
// walks the same calls in the same order from zero, so the sequence is the same every run.
var attempts: usize = 0;

// The ways connecting fails, in the order an attempt meets them. Each one is a different branch in
// a caller that inspects the error: refused is a server that is not there, reset is one that hung
// up mid-handshake, unreachable is a network with no route, and a timeout is the one that a retry
// loop treats differently from the rest.
const connect_failures = [_]net.IpAddress.ConnectError{
    error.ConnectionRefused,
    error.Timeout,
    error.ConnectionResetByPeer,
    error.NetworkUnreachable,
    error.HostUnreachable,
};

// The ways a name fails to resolve. Kept separate from the connect list because code that handles
// "no such host" almost never handles it in the same place as "the connection was refused".
const lookup_failures = [_]net.HostName.LookupError{
    error.UnknownHostName,
    error.NameServerFailure,
    error.NoAddressReturned,
};

// The next failure from a list, advancing the rotation by one. Every entry point draws from the
// same counter, so a caller that looks up a name and then connects sees the two lists move
// together rather than each repeating its first entry forever.
fn next(comptime failures: anytype) @TypeOf(failures[0]) {
    const chosen = failures[attempts % failures.len];
    attempts +%= 1;
    return chosen;
}

// Layers the simulated network over `io`, leaving everything else it does alone: the thread pool,
// the clock, the files and the writers are the real ones, and only what would reach a machine is
// replaced. The vtable is written into `room` rather than returned by value, because an `Io` holds
// a pointer to its vtable and one on this function's stack would be gone by the time it is read.
pub fn simulated(io: std.Io, room: *std.Io.VTable) std.Io {
    room.* = io.vtable.*;
    room.netLookup = lookup;
    room.netConnectIp = connectIp;
    room.netListenIp = listenIp;
    room.netBindIp = bindIp;
    room.netAccept = accept;
    room.netConnectUnix = connectUnix;
    room.netListenUnix = listenUnix;
    room.netSocketCreatePair = socketCreatePair;
    return .{ .userdata = io.userdata, .vtable = room };
}

fn lookup(
    _: ?*anyopaque,
    _: net.HostName,
    _: *std.Io.Queue(net.HostName.LookupResult),
    _: net.HostName.LookupOptions,
) net.HostName.LookupError!void {
    return next(lookup_failures);
}

fn connectIp(
    _: ?*anyopaque,
    _: *const net.IpAddress,
    _: net.IpAddress.ConnectOptions,
) net.IpAddress.ConnectError!net.Socket {
    return next(connect_failures);
}

// Binding and listening are refused for the same reason connecting is: a port is a machine-wide
// resource, and several runs share a machine here.
fn listenIp(
    _: ?*anyopaque,
    _: *const net.IpAddress,
    _: net.IpAddress.ListenOptions,
) net.IpAddress.ListenError!net.Socket {
    return error.AddressInUse;
}

fn bindIp(
    _: ?*anyopaque,
    _: *const net.IpAddress,
    _: net.IpAddress.BindOptions,
) net.IpAddress.BindError!net.Socket {
    return error.AddressInUse;
}

fn accept(
    _: ?*anyopaque,
    _: net.Socket.Handle,
    _: net.Server.AcceptOptions,
) net.Server.AcceptError!net.Socket {
    return error.ConnectionAborted;
}

fn connectUnix(_: ?*anyopaque, _: *const net.UnixAddress) net.UnixAddress.ConnectError!net.Socket.Handle {
    return error.FileNotFound;
}

fn listenUnix(
    _: ?*anyopaque,
    _: *const net.UnixAddress,
    _: net.UnixAddress.ListenOptions,
) net.UnixAddress.ListenError!net.Socket.Handle {
    return error.AddressInUse;
}

fn socketCreatePair(_: ?*anyopaque, _: net.Socket.CreatePairOptions) net.Socket.CreatePairError![2]net.Socket {
    return error.SystemResources;
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("network.test.zig");
}
