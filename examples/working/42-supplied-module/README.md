# A module the project supplies

The code under test imports `units` by name. Nothing in the source says where that module is: `build.zig` builds it and hands it to `addFaultTest` as `.imports`, which is how a project gives the run the same modules its own build gives its code.

The module is built against the annotation channel the run compiles against, `faultline.module("log")`. A `log` module built separately for it would be a second copy of the same source in one binary, which Zig refuses.
