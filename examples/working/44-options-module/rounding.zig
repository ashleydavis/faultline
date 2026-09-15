// The code under test, marking its branches with the project's own `an` rather than the tool's.

const markers = @import("markers.zig");
const Log = markers.Log;
const an = markers.an;
const annotate = markers.annotate;

// The value, never above the ceiling. Two paths: one that had to be cut down and one that did not.
pub fn atMost(log: Log, value: u32, ceiling: u32) u32 {
    if (value > ceiling) {
        if (an) annotate(log, "atMost-cut-down", "", .{});
        return ceiling;
    }
    return value;
}
