// One of this project's two packages. Each is walked, compiled and reported on its own.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Whether every letter is upper case. Two paths: a letter that is not, and running off the end.
pub fn isShouted(log: Log, text: []const u8) bool {
    for (text) |letter| {
        if (an) annotate(log, "isShouted-reading", "", .{});
        if (letter >= 'a' and letter <= 'z') {
            if (an) annotate(log, "isShouted-lower-case", "", .{});
            return false;
        }
    }
    return true;
}
