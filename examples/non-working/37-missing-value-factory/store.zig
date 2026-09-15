const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A store addressed as one dispatch point and a context beside it. Nothing can be built from this
// type alone: a function pointer has no value a signature decides, and there is no factory for it
// anywhere in this project.
pub const Store = struct {
    ctx: *anyopaque,
    read: *const fn (ctx: *anyopaque, key: []const u8) ?[]const u8,
};

// Never called at all, because the run cannot build a `Store` to hand it.
pub fn valueFor(log: Log, store: Store, key: []const u8) []const u8 {
    if (store.read(store.ctx, key)) |found| {
        if (an) annotate(log, "valueFor-found", "", .{});
        return found;
    } else {
        if (an) annotate(log, "valueFor-missing", "", .{});
    }
    return "";
}

// Called, and fully covered, so the report has something to contrast the one above with.
pub fn keyLength(key: []const u8) usize {
    return key.len;
}
