# A function that never returns

For one of its inputs the loop has no way out. The run gives every call five seconds of processor time, steps over the one that spends them, and carries on with the rest rather than hanging with it.

The report says how many calls were stepped over and how many of those were for spending their time rather than for crashing. The paths inside the loop are not counted as covered, so the run ends below a hundred per cent.

Returns `error.SimCoveragePathsUnticked`.
