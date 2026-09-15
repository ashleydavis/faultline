const std = @import("std");
const output_mod = @import("output.zig");
const Point = @import("point.zig").Point;

// Prints what a failing run needs to be reproduced: the point that failed, the failure that was
// injected there, and the error that came back, followed by the exact command that runs this one
// case directly with no sweep and no search. This is what turns a failure buried among many
// injected runs into something a person can go straight back to.
pub fn printFailure(point: Point, failure_name: []const u8, err: anyerror) void {
    output_mod.print("Failing {f} with {s} failed the run with {t}.\n", .{ point, failure_name, err });
    output_mod.print("Reproduce it with: flt --replay \"{f}={s}\"\n", .{ point, failure_name });
}

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("report.test.zig");
}
