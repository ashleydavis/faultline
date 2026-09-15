# A generic function only a scenario can call

`values: []const T` is written in terms of the function's own type parameter, so what it takes is not known until the function is instantiated and the run has nothing to make an argument from. The run leaves the function alone and counts its paths as uncovered, and the scenario beside it calls it with the types the run cannot choose.

A signature reads the same to the compiler whether that parameter is `[]const T` or `anytype`, so the walk reads the source to tell them apart. Before it did, a project like this one stopped the run with a compile error inside the tool.
