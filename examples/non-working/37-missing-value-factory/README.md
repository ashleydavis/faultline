# A function needing a test input factory

`valueFor` takes a type holding a function pointer, which has no value a signature decides, and this project declares no factory for it. The function is never called at all, so none of its paths run, and the checklist names the function, the type it cannot build and what to write.

Returns `error.SimCoveragePathsUnticked`.
