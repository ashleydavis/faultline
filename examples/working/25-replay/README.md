# Reproducing one run

`flt --replay "<plan>"` runs a strict subset of an ordinary run: the seed the plan names, and the injected faults it names. Copying what the report printed is the whole of reproducing a failure, with no working out which kind of failure it was.

This example is run with `--replay "seed=2"`, which is why it reports a replay rather than a report.
