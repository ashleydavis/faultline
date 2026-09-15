// Code whose consistency has to hold whichever point failed, checked by invariants the example
// registers.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A running total and the entries behind it, which have to agree however a write fails.
pub const Ledger = struct {
    total: i64 = 0,
    entries: i64 = 0,

    pub fn add(self: *Ledger, log: Log, amount: i64) void {
        if (amount == 0) {
            if (an) annotate(log, "add-nothing-to-add", "", .{});
            return;
        } else {
            if (an) annotate(log, "add-added", "", .{});
        }
        self.total += amount;
        self.entries += 1;
    }
};
