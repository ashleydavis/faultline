// A generic function the run cannot call for itself: `values` is written in terms of `T`, so what
// it takes is not known until the function is instantiated and the run has nothing to make an
// argument from. It leaves the function alone and asks for a scenario, which is below.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// The largest of the values, or nothing when there are none.
pub fn largest(log: Log, comptime T: type, values: []const T) ?T {
    if (values.len == 0) {
        if (an) annotate(log, "largest-none", "", .{});
        return null;
    }
    var highest = values[0];
    for (values[1..]) |value| {
        if (an) annotate(log, "largest-comparing", "", .{});
        if (value > highest) {
            if (an) annotate(log, "largest-a-new-highest", "", .{});
            highest = value;
        } else {
            if (an) annotate(log, "largest-no-higher", "", .{});
        }
    }
    return highest;
}
