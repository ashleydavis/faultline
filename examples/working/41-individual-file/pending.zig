const annotate_mod = @import("log");
const Log = annotate_mod.Log;
const an = annotate_mod.an;
const annotate = annotate_mod.annotate;

// Deliberately short of annotations, and deliberately not what the run was narrowed to. Its
// unreached paths are what prove the run counted only the other file.
pub fn describe(value: u8) []const u8 {
    if (value == 0) {
        return "none";
    }
    if (value == 1) {
        return "one";
    }
    return "many";
}
