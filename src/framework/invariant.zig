const std = @import("std");

// Whether a registered check runs after every injected run or only after a sample of them.
// A full consistency pass over a simulated store
// costs more than the injection it is checking, so it is sampled rather than run every time; a
// check for a leak or a handle left open is cheap enough to run after every one.
pub const Cost = enum { cheap, expensive };

// One thing that has to hold no matter which point failed. A package registers these to say what
// "handled correctly" means for it; `search.zig` runs them and knows nothing else about what they
// check.
pub const Invariant = struct {
    // What a violation is reported as.
    name: []const u8,

    cost: Cost,

    // What `check` reads: a pointer to whatever state the invariant is about, such as a store or
    // the recording log a run built.
    ctx: *anyopaque,

    // Returns an error when the invariant does not hold. `exploreAll` treats that exactly like the
    // run itself failing: the plan that produced it is printed and the error propagates.
    check: *const fn (ctx: *anyopaque) anyerror!void,
};

test {
    //
    // The tests live in their own file so a change to them is never mistaken for a change to the
    // code. Nothing else imports that file, so naming it here is what runs it.
    //
    _ = @import("invariant.test.zig");
}
