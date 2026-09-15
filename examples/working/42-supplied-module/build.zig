const std = @import("std");

pub fn build(b: *std.Build) void {
    const faultline = b.dependency("faultline", .{});

    // The module the code under test imports, built against the annotation channel the run itself
    // compiles against. Building `log` separately here instead would put two copies of it in the
    // one binary, which Zig refuses.
    const units = b.createModule(.{
        .root_source_file = b.path("units.zig"),
        .imports = &.{.{ .name = "log", .module = faultline.module("log") }},
    });

    @import("faultline").addFaultTest(b, .{
        .imports = &.{.{ .name = "units", .module = units }},
    });
}
