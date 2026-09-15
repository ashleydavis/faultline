// The factory for `Feed`, and the state it reads.
//
// The state's fields are filled from their own types, so the run builds a different one on every
// call and the factory hands back a feed that behaves differently each time without anything here
// saying how.

const sim = @import("sim");
const feed_mod = @import("feed.zig");

// What a made `Feed` reads from. Both fields are filled from their types: one run gets a feed with
// nothing in it, another gets one with several values.
pub const Counted = struct {
    values: [4]u8 = .{ 0, 0, 0, 0 },
    left: u8 = 0,

    fn next(ctx: *anyopaque) ?u8 {
        const self: *Counted = @ptrCast(@alignCast(ctx));
        if (self.left == 0) {
            return null;
        }
        self.left -= 1;
        return self.values[self.left % self.values.len];
    }
};

pub fn feedFrom(state: *Counted) feed_mod.Feed {
    return .{ .ctx = state, .next = Counted.next };
}
