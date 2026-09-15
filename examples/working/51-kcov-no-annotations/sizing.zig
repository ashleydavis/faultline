// No annotation and no `Log` anywhere in this file. Every path is proved by its own line running,
// which kcov reports, so every function here is covered without a line being added to it.

pub const Size = enum { small, medium, large };

// An `if` with an `else if` and an `else`: three sides, each with a line of its own.
pub fn classify(value: u32) Size {
    if (value < 10) {
        return .small;
    } else if (value < 1000) {
        return .medium;
    } else {
        return .large;
    }
}

// A `switch` with an arm written as a block and an arm written as a bare expression on a line of
// its own. Both have a line that proves them.
pub fn label(size: Size) []const u8 {
    switch (size) {
        .small => {
            return "small";
        },
        .medium => return "medium",
        .large => {
            return "large";
        },
    }
}

// A loop whose body's first line proves the loop went round.
pub fn total(values: []const u32) u64 {
    var sum: u64 = 0;
    for (values) |value| {
        sum += value;
    }
    return sum;
}
