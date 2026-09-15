const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Every path of this function is reached, so the last line of the run reads 100% and the run exits
// zero. That is the whole of what the number is for: below a hundred, the run is red.
pub fn sign(log: Log, value: i32) i8 {
    if (value > 0) {
        if (an) annotate(log, "sign-positive", "", .{});
        return 1;
    } else {
        if (an) annotate(log, "sign-not-positive", "", .{});
    }
    if (value < 0) {
        if (an) annotate(log, "sign-negative", "", .{});
        return -1;
    } else {
        if (an) annotate(log, "sign-zero", "", .{});
    }
    return 0;
}
