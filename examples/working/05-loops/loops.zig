// Loops, each with the one annotation a loop's path is named by: the first statement of its body,
// saying the body ran.

const std = @import("std");
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A `while` whose body may or may not run.
pub fn countDown(log: Log, from: u8) usize {
    var left = from;
    var steps: usize = 0;
    while (left > 0) {
        if (an) annotate(log, "countDown-loop-iteration", "", .{});
        left -= 1;
        steps += 1;
    }
    return steps;
}

// A `for` over a slice, which is the ordinary case.
pub fn longest(log: Log, words: []const []const u8) usize {
    var best: usize = 0;
    for (words) |word| {
        if (an) annotate(log, "longest-loop-iteration", "", .{});
        if (word.len > best) {
            if (an) annotate(log, "longest-longer", "", .{});
            best = word.len;
        } else {
            if (an) annotate(log, "longest-no-longer", "", .{});
        }
    }
    return best;
}

// A table this file declares from a literal, which the loop below walks.
const known_sizes = [_]usize{ 1, 2, 4 };

// A `for` over a table the file declares.
pub fn largestKnown(log: Log) usize {
    var best: usize = 0;
    for (known_sizes) |size| {
        if (an) annotate(log, "largestKnown-loop-iteration", "", .{});
        best = @max(best, size);
    }
    return best;
}
