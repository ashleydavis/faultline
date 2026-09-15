# An if with a capture

`if (x) |value|` over an optional with the missing side left off, and `if (x) |value| else |e|` over an error union with both sides written.

It also carries an `orelse`, which is a branch written as an expression: the annotation goes inside the fallback itself.
