// Every branch here is annotated, so the run reaches every path from annotations alone. The run is
// given a kcov that does not exist, says so in one line, and carries on exactly as it did before
// kcov.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

pub fn classify(log: Log, count: usize) usize {
    if (count == 0) {
        if (an) annotate(log, "classify-empty", "", .{});
        return 0;
    } else {
        if (an) annotate(log, "classify-not-empty", "", .{});
        return count;
    }
}
