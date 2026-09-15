const std = @import("std");

pub fn build(b: *std.Build) void {
    @import("faultline").addFaultTest(b, .{
        // The benchmarks are code, so the walk takes them for source and asks for their paths to be
        // covered as well. A benchmark exercises the code rather than being the code exercised, and
        // nothing in a tree says which is which, so it is named here.
        .exclude = &.{"bench"},
    });
}
