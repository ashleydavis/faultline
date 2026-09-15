const std = @import("std");

pub fn build(b: *std.Build) void {
    @import("faultline").addFaultTest(b, .{
        // The name this project's code reads its build options from. This project's ordinary build
        // supplies that module itself, with the markers off; the run supplies its own under the
        // same name, with them on. Without this the run compiles code importing `build_options`
        // and the compiler has no module of that name.
        .options_module = "build_options",
    });
}
