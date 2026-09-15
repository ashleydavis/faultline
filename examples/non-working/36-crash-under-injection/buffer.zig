const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Reads the value at an index without checking it, which is fine until the fill is refused and the
// list is shorter than the caller assumed.
pub fn firstOf(values: []const u8) u8 {
    return values[0];
}
