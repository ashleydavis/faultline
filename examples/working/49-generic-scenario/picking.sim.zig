// One scenario, calling the generic function with the types the run cannot choose for it.

const sim = @import("sim");
const picking = @import("picking.zig");
const Subject = sim.Subject(@import("log").Log);

pub fn runLargestScenario(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
    _ = checklist;
    _ = injector;

    if (picking.largest(self.log, u8, &.{}) != null) {
        return error.EmptyHadALargest;
    }
    if (picking.largest(self.log, u8, &.{ 3, 9, 4 }) != 9) {
        return error.LargestNotFound;
    }
}
