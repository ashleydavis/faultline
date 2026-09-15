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

// This one takes no `Log`, so it has nowhere to send an annotation, and both of its branches sit on
// the line of their own condition, so no line can prove either of them ran. Under kcov a body on a
// line of its own would be proved by that line; these two are not, and only an annotation could
// prove them, which the function has nowhere to send.
pub fn hashBytes(value: u32) usize {
    var hash: usize = 0;
    if (value == 0) return 1;
    hash = value;
    if (hash > 100) hash = 100;
    return hash;
}
