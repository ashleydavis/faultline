// A module of the project's own, named in `build.zig` and reached by that name from the code that
// uses it. It is source like any other, so its own branches are exercised and counted too.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Bytes as whole kilobytes, rounding down. Two paths: under a kilobyte and over it.
pub fn kilobytes(log: Log, bytes: usize) usize {
    if (bytes < 1024) {
        if (an) annotate(log, "kilobytes-under-one", "", .{});
        return 0;
    }
    return bytes / 1024;
}
