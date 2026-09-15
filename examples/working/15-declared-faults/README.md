# Faults a factory's state declares

An enum field on a factory's state is filled from its own type like any other, so the run builds the state once per value of the enum and every failing side of the code that reads it is reached. Nothing registers a list of faults anywhere.
