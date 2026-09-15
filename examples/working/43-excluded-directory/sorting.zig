// The code under test. One file, and the only file the run measures: `bench/` is named in
// `build.zig` as code to leave out.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Whether the numbers are in order. Two paths: one out of order ends it, and running off the end
// says they are in order.
pub fn inOrder(log: Log, numbers: []const u8) bool {
    var index: usize = 1;
    while (index < numbers.len) : (index += 1) {
        if (an) annotate(log, "inOrder-comparing", "", .{});
        if (numbers[index] < numbers[index - 1]) {
            if (an) annotate(log, "inOrder-out-of-order", "", .{});
            return false;
        }
    }
    return true;
}
