// `if` over an optional and over an error union, both with their capture written out.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// What `sizeOf` below calls, so its `if` has a real error union to take apart.
fn measure(log: Log, refuse: bool) !usize {
    if (refuse) {
        if (an) annotate(log, "measure-refused", "", .{});
        return error.Refused;
    } else {
        if (an) annotate(log, "measure-measured", "", .{});
    }
    return 7;
}

// `if (x) |value|` with the missing side written as an `else` holding only its annotation.
pub fn lengthOr(log: Log, text: ?[]const u8, fallback: usize) usize {
    if (text) |value| {
        if (an) annotate(log, "lengthOr-present", "", .{});
        return value.len;
    } else {
        if (an) annotate(log, "lengthOr-absent", "", .{});
    }
    return fallback;
}

// `orelse` is a branch wherever it appears: the fallback ran, or the value came back and it did
// not. It is written as an expression, so the annotation goes on the fallback itself.
pub fn lengthOrDefault(log: Log, text: ?[]const u8) usize {
    const found = text orelse blk: {
        if (an) annotate(log, "lengthOrDefault-fell-back", "", .{});
        break :blk "";
    };
    return found.len;
}

// `if (x) |value| else |e|` over an error union: both sides written, both annotated.
pub fn sizeOf(log: Log, refuse: bool) usize {
    if (measure(log, refuse)) |value| {
        if (an) annotate(log, "sizeOf-value", "", .{});
        return value;
    } else |_| {
        if (an) annotate(log, "sizeOf-error", "", .{});
        return 0;
    }
}
