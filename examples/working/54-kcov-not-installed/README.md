# A run without kcov

The build is told to use a kcov binary that is not there. The run prints one line saying coverage comes from annotations alone, and because every branch here is annotated it still reaches every path.

Exits 0.
