# A project that reads its own build options

The code marks its branches with an `an` of its own, read from `build_options`, which is this project's own options module rather than the one the tool hands out. That is what lets a release build of the project compile the markers away while a run keeps them.

`build.zig` names that module in `.options_module`. Without it the run compiles code importing `build_options` and the compiler has no module of that name.
