// A path nothing the run makes up reaches, exercised by a scenario written beside the module.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A lock that refuses a second holder. Taking it twice is a path no single call can reach: it needs
// two calls in an order, which is what a scenario is for.
pub const Lock = struct {
    held: bool = false,

    pub fn take(self: *Lock, log: Log) bool {
        if (self.held) {
            if (an) annotate(log, "take-already-held", "", .{});
            return false;
        } else {
            if (an) annotate(log, "take-taken", "", .{});
        }
        self.held = true;
        return true;
    }

    pub fn release(self: *Lock) void {
        self.held = false;
    }
};
