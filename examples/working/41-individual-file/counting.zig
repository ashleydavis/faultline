const annotate_mod = @import("log");
const Log = annotate_mod.Log;
const an = annotate_mod.an;
const annotate = annotate_mod.annotate;

// The file the run is narrowed to. Every branch carries an annotation, so every path can tick.
pub fn countOver(log: Log, values: []const u8, floor: u8) usize {
    var seen: usize = 0;
    for (values) |value| {
        if (an) annotate(log, "countOver:loop-iteration", "", .{});
        if (value > floor) {
            if (an) annotate(log, "countOver:above", "", .{});
            seen += 1;
        } else {
            if (an) annotate(log, "countOver:not-above", "", .{});
        }
    }
    return seen;
}
