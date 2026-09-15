const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// The false side of this `if` carries no annotation, and needs none: the run counts the two lines
// below against each other to decide whether it ran.
pub fn isLarge(log: Log, value: u32) bool {
    if (value > 1000) {
        if (an) annotate(log, "isLarge-large", "", .{});
        return true;
    }
    return false;
}
