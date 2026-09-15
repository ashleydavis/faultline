# An argument the build does not take

`zig build flt -Deverything` names a build option Faultline does not declare, and the build refuses it before any fault testing starts.

The refusal comes from Zig rather than from Faultline, which is the point: the options a run takes are declared in the build, so naming one that does not exist is a build error with the list of the ones that do.
