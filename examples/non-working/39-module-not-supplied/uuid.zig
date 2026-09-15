const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// This file imports a module the command was not given, so it will not compile. The run names the
// module, prints the compiler's own error, and says which argument supplies it.
const shortid = @import("shortid");

pub fn nextId() []const u8 {
    return shortid.generate();
}
