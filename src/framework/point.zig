const std = @import("std");

// Where a simulated effect can fail, named by where it is in the source rather than by a counter:
// two runs of the same binary agree on a point's identity without either one having to renumber
// anything when a line is added above it. `occurrence` distinguishes more than one point on the
// same line (a call site inside a loop, or two `check` calls on one line), and is supplied by the
// caller rather than counted here, since only the caller knows which of its own calls is which.
pub const Point = struct {
    // The source file the point is in, exactly as `@src().file` reports it.
    file: []const u8,

    // The line the point is on, exactly as `@src().line` reports it.
    line: u32,

    // Which occurrence at that line this is, for a line reached more than once with a distinct
    // point each time. Zero for a line reached only one way.
    occurrence: u16,

    // Whether two points name the same place.
    pub fn eql(self: Point, other: Point) bool {
        return self.line == other.line and
            self.occurrence == other.occurrence and
            std.mem.eql(u8, self.file, other.file);
    }

    // Formats a point the way a plan and a reproduce command both read it: "file:line#occurrence".
    pub fn format(self: Point, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}:{d}#{d}", .{ self.file, self.line, self.occurrence });
    }
};

// What failing looks like at a point. An effect declares its own list of these; the framework
// never interprets `err` or `data`, only carries them from the effect that named them to the
// injector that hands one back.
pub const Failure = struct {
    // What a plan names this failure as, e.g. "connection_refused". Matched against a plan's own
    // text by `plan.zig`, so this is what a person types after `--replay`.
    name: []const u8,

    // What the effect returns when this failure is chosen.
    err: anyerror,

    // For a failure that carries a value beyond an error, such as a short write's byte count. Most
    // failures need nothing here.
    data: ?[]const u8 = null,
};

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("point.test.zig");
}
