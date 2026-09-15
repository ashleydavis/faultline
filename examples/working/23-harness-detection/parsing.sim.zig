// A file that imports the framework, which is what makes it harness code: it exercises the run rather
// than being measured by it, so it is given no checklist of its own however many functions it
// declares. Nothing lists which files are harness, so nothing goes stale when one is added.

const sim = @import("sim");
const parsing_mod = @import("parsing.zig");
const Subject = sim.Subject(@import("log").Log);

// A function declared in harness code. It has branches, and none of them is on any checklist.
pub fn runDigitsScenario(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
    _ = checklist;
    _ = injector;
    if (parsing_mod.digitsIn(self.log, "a1b2") != 2) {
        return error.CountedWrong;
    }
}
