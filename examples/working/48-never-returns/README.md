# A function that never returns

For one of its inputs the loop has no way out. The run gives every call five seconds of processor time, steps over the one that spends them, and carries on with the rest rather than hanging with it.

The report says how many calls were stepped over and how many of those were for spending their time rather than for crashing. The call that never returned annotated nothing, because a call hands its annotations over when it comes back, but kcov saw the lines inside the loop run, so the paths inside it count as covered and the run ends at a hundred per cent.

Exits 0.
