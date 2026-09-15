# A function with nowhere to send its annotations

`hashBytes` takes no `Log`, so it cannot annotate anything and every one of its paths goes unticked however hard the run drives it. The checklist says to give it a `Log` parameter and how many paths that is costing.

Returns `error.SimCoveragePathsUnticked`.
