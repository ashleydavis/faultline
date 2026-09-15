// The factory for `Store`, which is what lets the run call every function that takes one.
//
// A factory takes a pointer to the state it is wired to and returns the type wanted. The state is
// built from its own type like any other value, so nothing here has to be registered anywhere.

const sim = @import("sim");
const store_mod = @import("store.zig");

// What a made `Store` reads from: one key and one value, both filled from their types, so the run
// gets a different store on every call.
pub const OneEntry = struct {
    key: []const u8 = "",
    value: []const u8 = "",

    fn read(ctx: *anyopaque, key: []const u8) ?[]const u8 {
        const self: *OneEntry = @ptrCast(@alignCast(ctx));
        if (std_mem_eql(self.key, key)) {
            return self.value;
        }
        return null;
    }
};

fn std_mem_eql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        return false;
    }
    for (a, b) |left, right| {
        if (left != right) {
            return false;
        }
    }
    return true;
}

// The factory itself: a pointer to the state first, the type wanted as the return.
pub fn storeFrom(state: *OneEntry) store_mod.Store {
    return .{ .ctx = state, .read = OneEntry.read };
}
