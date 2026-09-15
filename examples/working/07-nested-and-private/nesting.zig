const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A private function, reached only through the public one below it. It gets a checklist of its own
// exactly as a public one does.
fn trimmedLength(log: Log, text: []const u8) usize {
    if (text.len == 0) {
        if (an) annotate(log, "trimmedLength-empty", "", .{});
        return 0;
    } else {
        if (an) annotate(log, "trimmedLength-has-text", "", .{});
    }
    return text.len;
}

// A function declared inside another, which gets its own checklist rather than the outer one's.
pub fn describe(log: Log, text: []const u8) usize {

    const Inner = struct {
        fn doubled(inner_log: Log, value: usize) usize {
            if (value > 10) {
                if (an) annotate(inner_log, "doubled-capped", "", .{});
                return 20;
            } else {
                if (an) annotate(inner_log, "doubled-doubled", "", .{});
            }
            return value * 2;
        }
    };

    return Inner.doubled(log, trimmedLength(log, text));
}
