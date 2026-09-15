// The smallest thing Faultline can measure: one function, no branches, one annotation saying it
// was entered.

const faultline = @import("log");
const Log = faultline.Log;

// The two names every annotated file pulls in unqualified. The walker that reads a function's
// branches looks for the literal text `if (an) annotate(...)`, so a qualified call would be a
// function call it does not recognise and the branch would read as unannotated.
const an = faultline.an;
const annotate = faultline.annotate;

// How long the name is. One path, which the annotation on its first statement is what ticks.
pub fn greet(name: []const u8) usize {
    return name.len;
}
