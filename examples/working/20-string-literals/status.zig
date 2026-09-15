// A branch that turns on the module comparing against a string the module itself declares, reached
// because the run reads a module's own literals and tries them.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// The status this module is written in terms of. There is nowhere else the run could get it from:
// the module names it, so the run reads it from here rather than being told.
const ok_status = "OK";

// Whether the response says everything is well.
pub fn succeeded(log: Log, status: []const u8) bool {
    if (std.mem.eql(u8, status, ok_status)) {
        if (an) annotate(log, "succeeded-ok", "", .{});
        return true;
    } else {
        if (an) annotate(log, "succeeded-not-ok", "", .{});
    }
    return false;
}
