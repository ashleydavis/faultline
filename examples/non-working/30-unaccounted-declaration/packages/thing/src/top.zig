const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Measured, because it sits in a directory the layout matches.
pub fn doubled(log: Log, value: u8) u16 {
    return @as(u16, value) * 2;
}
