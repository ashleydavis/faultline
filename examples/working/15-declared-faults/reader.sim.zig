// The factory for `Source`, whose state carries an enum of the ways reading can go wrong.
//
// Nothing registers that list anywhere. An enum field is filled from its own type like any other,
// so the run builds this state once per value and every side of the code that reads it is reached.

const sim = @import("sim");
const reader_mod = @import("reader.zig");

// What a made `Source` does when it is read.
pub const Fault = enum { none, empty, broken };

pub const Scripted = struct {
    fault: Fault = .none,
    byte: u8 = 0,

    fn read(ctx: *anyopaque) anyerror!u8 {
        const self: *Scripted = @ptrCast(@alignCast(ctx));
        return switch (self.fault) {
            .none => self.byte,
            .empty => error.Empty,
            .broken => error.Broken,
        };
    }
};

pub fn sourceFrom(state: *Scripted) reader_mod.Source {
    return .{ .ctx = state, .read = Scripted.read };
}
