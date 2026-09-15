// A function taking a random source, which draws from the run's own seeded one so the same seed
// draws the same sequence.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// Picks one of the words. The draw comes from the run's seeded source, so two runs of the same seed
// pick the same one.
pub fn pick(log: Log, random: std.Random, words: []const []const u8) []const u8 {
    if (words.len == 0) {
        if (an) annotate(log, "pick-nothing-to-pick", "", .{});
        return "";
    } else {
        if (an) annotate(log, "pick-picked", "", .{});
    }
    return words[random.uintLessThan(usize, words.len)];
}
