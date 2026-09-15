const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A running total that goes negative when a write is refused part way through, which is what the
// invariant beside the scenarios catches.
pub const Ledger = struct {
    total: i64 = 0,

    pub fn take(self: *Ledger, log: Log, amount: i64) void {
        if (amount == 0) {
            if (an) annotate(log, "take-nothing-to-take", "", .{});
            return;
        } else {
            if (an) annotate(log, "take-taken", "", .{});
        }
        self.total -= amount;
    }
};
