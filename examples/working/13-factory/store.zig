// A type of the project's own holding a function pointer, which the run cannot build from its
// type, reached through a factory beside the module that declares it.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A store addressed as one dispatch point and a context beside it. Nothing can be built from this
// type alone: a function pointer has no value a signature decides.
pub const Store = struct {
    ctx: *anyopaque,
    read: *const fn (ctx: *anyopaque, key: []const u8) ?[]const u8,
};

// Reads a key out of whatever store it was handed. Without a factory for `Store` this is never
// called at all.
pub fn valueFor(log: Log, store: Store, key: []const u8) []const u8 {
    if (store.read(store.ctx, key)) |found| {
        if (an) annotate(log, "valueFor-found", "", .{});
        return found;
    } else {
        if (an) annotate(log, "valueFor-missing", "", .{});
    }
    return "";
}
