# A seed scenario that fails

The scenario returns an error, so the run says which seed failed, in which directory, with which error, and prints the one command that reproduces it.

Prints `sim: seed <n> failed in <directory>: <error>` followed by `sim: reproduce with: flt --replay "seed=<n>"`.
