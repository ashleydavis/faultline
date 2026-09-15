# A file that opens and will not read

The filesystem a run installs is held in memory, so a function that reads a file never touches the machine and leaves nothing behind. Files a scenario needs are made there and disappear with the run.

Three paths through one function, none of them reachable by calling it with made up arguments: no such file, a file that opens and then fails to read, and a file with nothing in it. `sim.filesystem.failReadsOf` is what asks for the second, because an in-memory read has nothing in it that can fail on its own.
