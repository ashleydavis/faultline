// A benchmark. It exercises the code rather than being code the tool is asked about, and it carries
// no annotations, so a run that walked it would ask for an annotation on every branch in here.
//
// `build.zig` names this directory in `.exclude`, which is what keeps it out of the walk.

const std = @import("std");
const sorting = @import("../sorting.zig");
const Log = @import("log").Log;

pub fn timeIt(log: Log, rounds: usize) usize {
    var reached: usize = 0;
    var round: usize = 0;
    while (round < rounds) : (round += 1) {
        if (sorting.inOrder(log, &.{ 1, 2, 3 })) {
            reached += 1;
        }
    }
    return reached;
}
