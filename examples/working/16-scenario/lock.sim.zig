// One scenario, for the path nothing else reaches.
//
// A scenario is found by its signature rather than by its name: the subject, an injector and a
// checklist. What it covered is read from what the code annotated while it ran, so it never says.

const sim = @import("sim");
const lock_mod = @import("lock.zig");
const Subject = sim.Subject(@import("log").Log);

pub fn runTakenTwiceScenario(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
    // The run reads what the code annotated, so a scenario never says what it covered.
    _ = checklist;
    _ = injector;

    var lock = lock_mod.Lock{};
    _ = lock.take(self.log);
    _ = lock.take(self.log);
    lock.release();
}
