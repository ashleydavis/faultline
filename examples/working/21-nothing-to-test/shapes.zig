// A file declaring no function at all, which is named on its own line as having nothing to test.
// That is not a shortfall: there is no checklist to build from a file with no function in it.

// What a caller passes around. Types alone, no behaviour.
pub const Point = struct {
    x: i32,
    y: i32,
};

pub const origin: Point = .{ .x = 0, .y = 0 };
