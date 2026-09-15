// A factory state with an enum field on it, so the run builds the state once per value of the
// enum and the failing sides of the code that uses it are reached without anything registering a
// list of faults.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Something to read bytes out of, addressed as one dispatch point and a context beside it.
pub const Source = struct {
    ctx: *anyopaque,
    read: *const fn (ctx: *anyopaque) anyerror!u8,
};

// Reads one byte and says what happened. Each way the source can fail takes a different side.
pub fn firstByte(log: Log, source: Source) u8 {
    const byte = source.read(source.ctx) catch |err| {
        if (an) annotate(log, "firstByte-failed", "", .{});
        switch (err) {
            error.Empty => {
                if (an) annotate(log, "firstByte-empty", "", .{});
                return 0;
            },
            else => {
                if (an) annotate(log, "firstByte-broken", "", .{});
                return 0;
            },
        }
    };
    return byte;
}
