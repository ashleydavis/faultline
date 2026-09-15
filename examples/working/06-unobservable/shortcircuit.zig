const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// What `inRange` calls, so the `try` below has something that can fail.
fn checkedHalf(log: Log, value: u8) !u8 {
    if (value % 2 != 0) {
        if (an) annotate(log, "checkedHalf-odd", "", .{});
        return error.Odd;
    } else {
        if (an) annotate(log, "checkedHalf-even", "", .{});
    }
    return value / 2;
}

// `and` and `or` are branches with nowhere to put an annotation: there is no statement position
// inside an expression. They are counted and reported, and they are never on the checklist.
pub fn inRange(value: u8, low: u8, high: u8) bool {
    return value >= low and value <= high;
}

// `or` is the same story.
pub fn atEdge(value: u8, low: u8, high: u8) bool {
    return value == low or value == high;
}

// `try` is an early return out of the function, which is a path through it that no annotation can
// sit on either.
pub fn halfOrNothing(log: Log, value: u8) !u8 {
    const half = try checkedHalf(log, value);
    return half;
}
