# The failures

Every directory here is a project that makes Faultline report something, and each one exits non-zero. The README beside each says what it provokes and what the run prints.

## Failures no example here provokes

These are the errors the tool's own source can return that nothing in a project can make it produce. Each one is written down with the reason, because a failure with no example is a failure nobody has seen the output of, and the reason is what says whether that is a gap or a fact about the error.

- `error.SourceDoesNotParse`: a source file that is not valid Zig stops the compiler before the run starts, so the run never reaches the point of parsing it itself.
- `error.FunctionNotFound`: a checklist is asked for a function by name and occurrence taken from the same source the run just read, so the only way to reach this is for the file to change between the compile and the run.
- `error.SimCannotFork` and `error.SimCannotOpenPipe`: the operating system refusing to start a process or open a pipe. Provoking either means exhausting the machine rather than writing a project.
- `error.CoverageRunCeilingReached` and `error.CoverageLevelTicklessLimitReached`: both come from `exploreCoverage`, which a project calls directly. Nothing the command runs calls it, so no project laid out for the command can reach either.
- `error.SimOperationFailed` and `error.SimSuppliedError`: the errors handed to a parameter that takes one, and to an operation the run stands in for. Both are returned to the code under test rather than to the run, so neither ends a run.
- The panic in `tallyIfRegistered`, for a name declared more than once in one package: the ordinary path finds a tally by name and occurrence together, which tells two same-named declarations apart, so nothing a project can write reaches the path that looks by name alone.
