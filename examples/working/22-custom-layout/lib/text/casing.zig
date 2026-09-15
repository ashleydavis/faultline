const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Whether the character is a lower-case letter.
pub fn isLowerCase(log: Log, character: u8) bool {
    if (character < 'a') {
        if (an) annotate(log, "isLowerCase-below", "", .{});
        return false;
    } else {
        if (an) annotate(log, "isLowerCase-not-below", "", .{});
    }
    if (character > 'z') {
        if (an) annotate(log, "isLowerCase-above", "", .{});
        return false;
    } else {
        if (an) annotate(log, "isLowerCase-in-range", "", .{});
    }
    return true;
}
