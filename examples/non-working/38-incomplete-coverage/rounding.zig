const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// One branch turns on a value nothing the run makes up ever produces, so the run ends below a
// hundred per cent. That is what the percentage on the last line and the non-zero exit are for.
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
    }
    // Nothing the run draws is this number, and nothing here hands it one, so this branch is never
    // taken and the run says so.
    if (value == 40_001) {
        if (an) annotate(log, "upTo-the-one-number-nothing-reaches", "", .{});
        return 0;
    }
    return value + (multiple - over);
}
