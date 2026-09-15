# A module the run was not given

`uuid.zig` imports `shortid`, which no `--module` supplied, so the simulation will not compile. The run prints the compiler's own error and the `--module shortid=<path>` that would fix it.

Returns `error.SimulationWillNotCompile`.
