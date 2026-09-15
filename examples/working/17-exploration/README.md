# An exploration

An exploration is found by its signature: an allocator and an injector. The run calls it once with an injector that records every point the code asked about, then once more for each of those points for each way it can fail, so every failing side is driven without a list of cases being written anywhere.
