# A generic function the run calls

One `comptime` type parameter and one `anytype` beside it is the one generic signature the run knows what to do with: it reads the untyped parameter as something to call that either answers or fails, supplies both, and varies how many of the calls fail first.

That reaches every side of a retry loop without a scenario. A generic whose untyped parameter means something else is left alone and asked for a scenario instead.
