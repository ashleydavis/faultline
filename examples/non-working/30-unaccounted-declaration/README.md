# A declaration with no coverage checklist

`packages/thing/src/deeper/hidden.zig` sits below the source directory rather than in it, so the default arrangement does not match it and no checklist is built for what it declares. The run reads the file anyway and says so, rather than leaving a file nothing measures looking exactly like one with nothing in it.

Prints `sim: UNACCOUNTED <file>:<line> "<name>" has no coverage checklist` and returns `error.SimCoverageEnumerationIncomplete`.
