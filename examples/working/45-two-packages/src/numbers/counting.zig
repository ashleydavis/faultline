// The other package. Nothing here imports the first: they are separate packages of one project, and
// the run reports each of them separately.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// How many of the numbers are above the floor.
pub fn above(log: Log, numbers: []const u8, floor: u8) usize {
    var counted: usize = 0;
    for (numbers) |number| {
        if (an) annotate(log, "above-reading", "", .{});
        if (number > floor) {
            if (an) annotate(log, "above-counted", "", .{});
            counted += 1;
        } else {
            // Inside a loop both sides need a mark of their own: the count of calls against the
            // count of times the `if` fired is what stands in for an `else` elsewhere, and a loop
            // can take either side any number of times in one call.
            if (an) annotate(log, "above-below-the-floor", "", .{});
        }
    }
    return counted;
}
