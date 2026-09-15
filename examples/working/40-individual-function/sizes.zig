const annotate_mod = @import("log");
const Log = annotate_mod.Log;
const an = annotate_mod.an;
const annotate = annotate_mod.annotate;

// Below the first threshold. Here so the file holds more than the one function the run is asked
// for, which is what makes this example show anything.
pub fn small(log: Log, value: u32) bool {
    if (value < 10) {
        if (an) annotate(log, "small:yes", "", .{});
        return true;
    } else {
        if (an) annotate(log, "small:no", "", .{});
        return false;
    }
}

// The one the run is narrowed to.
pub fn middle(log: Log, value: u32) bool {
    if (value < 10) {
        if (an) annotate(log, "middle:below", "", .{});
        return false;
    } else {
        if (an) annotate(log, "middle:not-below", "", .{});
    }
    if (value > 100) {
        if (an) annotate(log, "middle:above", "", .{});
        return false;
    } else {
        if (an) annotate(log, "middle:within", "", .{});
        return true;
    }
}

// Above the second threshold. Here for the same reason as `small`.
pub fn large(log: Log, value: u32) bool {
    if (value > 100) {
        if (an) annotate(log, "large:yes", "", .{});
        return true;
    } else {
        if (an) annotate(log, "large:no", "", .{});
        return false;
    }
}
