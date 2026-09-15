const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// The two halves of the phrase this module compares against. The run reads the strings a module is
// written in terms of and tries them, but neither of these is the phrase: it is put together at
// compile time, so no literal in this file equals it and nothing the run makes up ever matches.
const opener = "open";
const ending = "-sesame";
const phrase = opener ++ ending;

// Whether the caller said the phrase. The matching side is annotated, so it has a name of its own,
// and nothing the run can make up reaches it.
pub fn opens(log: Log, said: []const u8) bool {
    if (std.mem.eql(u8, said, phrase)) {
        if (an) annotate(log, "opens-said-the-phrase", "", .{});
        return true;
    } else {
        if (an) annotate(log, "opens-said-something-else", "", .{});
    }
    return false;
}
