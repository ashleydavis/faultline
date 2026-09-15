const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Not measured: the default arrangement is `packages/<name>/src`, and this sits below that rather
// than in it, so no checklist is built for anything declared here. The run reads the file anyway,
// which is what makes it say so rather than leaving the gap silent.
pub fn tripled(log: Log, value: u8) u16 {
    return @as(u16, value) * 3;
}
