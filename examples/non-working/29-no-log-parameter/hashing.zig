const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// This function has somewhere to send its annotations, so its own paths tick.
pub fn describe(log: Log, value: u32) usize {
    if (value == 0) {
        if (an) annotate(log, "describe-nothing-to-hash", "", .{});
        return 0;
    }
    if (an) annotate(log, "describe-hashing", "", .{});
    return hashBytes(value);
}

// This one takes no `Log`, so it has nowhere to send an annotation and none of its paths can ever
// be ticked however hard the run exercises it.
pub fn hashBytes(value: u32) usize {
    var hash: usize = 0;
    if (value == 0) {
        return 1;
    }
    hash = value;
    if (hash > 100) {
        hash = 100;
    }
    return hash;
}
