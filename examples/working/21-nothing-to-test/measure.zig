const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

const shapes = @import("shapes.zig");

// The one function in this example, so the run has something to exercise.
pub fn quadrant(log: Log, point: shapes.Point) u8 {
    if (point.x >= 0) {
        if (an) annotate(log, "quadrant-right", "", .{});
        if (point.y >= 0) {
            if (an) annotate(log, "quadrant-upper-right", "", .{});
            return 1;
        } else {
            if (an) annotate(log, "quadrant-lower-right", "", .{});
        }
        return 4;
    } else {
        if (an) annotate(log, "quadrant-left", "", .{});
    }
    if (point.y >= 0) {
        if (an) annotate(log, "quadrant-upper-left", "", .{});
        return 2;
    } else {
        if (an) annotate(log, "quadrant-lower-left", "", .{});
    }
    return 3;
}
