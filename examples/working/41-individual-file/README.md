# An individual test over one file

`--file <path>` exercises the functions in that file and no others, and counts only its paths.

`counting.zig` is fully annotated and `pending.zig` is not. The run is asked for the first, so it reaches every path it counts and exits zero while the second still has work outstanding. That is the difference between an individual test and a complete test run: the number is about the file that was asked for, and says nothing about the rest of the repository.
