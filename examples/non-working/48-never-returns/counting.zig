// A function that never comes back for one of its inputs. The run gives every call five seconds of
// processor time, steps over the call that spends them, and carries on with the next.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// One less, except for the one value it never answers for.
pub fn oneLess(log: Log, from: u32) u32 {
    if (from == 0) {
        if (an) annotate(log, "oneLess-round-forever", "", .{});
        var spun: usize = 0;
        while (true) : (spun += 1) {
            if (an) annotate(log, "oneLess-still-going", "", .{});
        }
    }
    if (an) annotate(log, "oneLess-ordinary", "", .{});
    return from -| 1;
}
