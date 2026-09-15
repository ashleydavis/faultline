const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Ordinary code. What this example is about is the argument, not the code.
pub fn twice(value: u8) u16 {
    return @as(u16, value) * 2;
}
