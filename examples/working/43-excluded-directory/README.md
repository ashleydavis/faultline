# A directory left out of the walk

`bench/` holds a benchmark: code that exercises this project rather than code the tool is being asked about. It carries no annotations, so a run that walked it would ask for one on every branch in it.

`build.zig` names the directory in `.exclude`, and the run reports one source file rather than two.
