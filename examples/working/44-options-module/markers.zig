// This project decides for itself whether the branch markers are compiled in, reading the flag from
// its own build options module rather than from the one the tool hands out.
//
// `build.zig` names that module in `.options_module`, which is what makes `build_options` resolve
// while a run is compiling this code. The run always supplies it with the flag on, because a run
// without the markers measures nothing.

const faultline = @import("log");

pub const Log = faultline.Log;
pub const annotate = faultline.annotate;
pub const an = @import("build_options").annotations_enabled;
