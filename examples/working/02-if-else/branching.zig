// An `if` with a written `else`, and an `if` whose false side holds nothing but its annotation.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Both sides of an `if` written out, each with an annotation of its own.
pub fn classify(log: Log, count: usize) usize {
    if (count == 0) {
        if (an) annotate(log, "classify-empty", "", .{});
        return 0;
    } else {
        if (an) annotate(log, "classify-not-empty", "", .{});
        return count;
    }
}

// An `if` whose false side does nothing but say it was taken, which is what an annotation is for
// when there is no work on that side.
pub fn doubleWhenSmall(log: Log, value: u8) u8 {
    if (value < 100) {
        if (an) annotate(log, "doubleWhenSmall-doubled", "", .{});
        return value * 2;
    } else {
        if (an) annotate(log, "doubleWhenSmall-left-alone", "", .{});
    }
    return value;
}
