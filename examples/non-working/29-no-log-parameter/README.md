# A function with nowhere to send its annotations

`hashBytes` takes no `Log`, so it cannot annotate anything, and both of its branches sit on the line of their own condition, so no line can prove either of them ran. The checklist says to give it a `Log` parameter and how many paths that is costing, and for each branch to put the body on a line of its own or annotate it.

Returns `error.SimCoveragePathsUnticked`.
