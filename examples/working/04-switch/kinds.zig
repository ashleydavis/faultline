// A switch as a statement, with a plain arm, a range arm, a multi-value arm and an else arm.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Every kind of arm a switch can have, each annotated on its first statement.
pub fn band(log: Log, value: u8) usize {
    switch (value) {
        0 => {
            if (an) annotate(log, "band-zero", "", .{});
            return 0;
        },
        1...9 => {
            if (an) annotate(log, "band-single-digit", "", .{});
            return 1;
        },
        10, 20, 30 => {
            if (an) annotate(log, "band-round", "", .{});
            return 2;
        },
        else => {
            if (an) annotate(log, "band-rest", "", .{});
            return 3;
        },
    }
}
