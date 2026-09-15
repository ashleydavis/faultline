// The code under test, reaching the project's own `units` module by name. Nothing here says where
// that module's source is: `build.zig` names it, and the run compiles against the same module the
// project's own build does.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

const units = @import("units");

// Whether a file of this size is worth storing whole, which it is once it rounds to a kilobyte.
pub fn storesWhole(log: Log, bytes: usize) bool {
    if (units.kilobytes(log, bytes) == 0) {
        if (an) annotate(log, "storesWhole-too-small", "", .{});
        return false;
    }
    return true;
}
