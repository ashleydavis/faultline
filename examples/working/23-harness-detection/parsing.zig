const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Ordinary code, which is what gets a checklist.
pub fn digitsIn(log: Log, text: []const u8) usize {
    var found: usize = 0;
    for (text) |character| {
        if (an) annotate(log, "digitsIn-loop-iteration", "", .{});
        if (character >= '0' and character <= '9') {
            if (an) annotate(log, "digitsIn-digit", "", .{});
            found += 1;
        } else {
            if (an) annotate(log, "digitsIn-not-a-digit", "", .{});
        }
    }
    return found;
}
