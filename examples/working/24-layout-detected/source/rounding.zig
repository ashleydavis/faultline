const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Rounds up to the next multiple.
pub fn upTo(log: Log, value: u16, multiple: u16) u16 {
    if (multiple == 0) {
        if (an) annotate(log, "upTo-no-multiple", "", .{});
        return value;
    } else {
        if (an) annotate(log, "upTo-has-multiple", "", .{});
    }
    const over = value % multiple;
    if (over == 0) {
        if (an) annotate(log, "upTo-already-round", "", .{});
        return value;
    } else {
        if (an) annotate(log, "upTo-rounded", "", .{});
    }
    return value + (multiple - over);
}
