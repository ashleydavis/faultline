// Two scenarios, because neither path can be reached by calling the function with made up arguments:
// one needs a file that exists, and the other needs one that opens and then fails to read.
//
// The filesystem a run installs is held in memory, so the file written here is never on the machine
// and the failure is asked for by name rather than arranged on a disk.

const std = @import("std");
const sim = @import("sim");
const settings = @import("settings.zig");
const Subject = sim.Subject(@import("log").Log);

pub fn runFileReadsScenario(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
    _ = checklist;
    _ = injector;

    var file = try std.Io.Dir.cwd().createFile(self.io, settings.settings_path, .{});
    var writer = file.writer(self.io, &.{});
    try writer.interface.writeAll("loud");
    try writer.interface.flush();
    file.close(self.io);

    var into: [16]u8 = undefined;
    const read = settings.setting(self.log, self.io, settings.settings_path, &into);
    if (!std.mem.eql(u8, read, "loud")) {
        return error.SettingNotRead;
    }
}

pub fn runFileWillNotReadScenario(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
    _ = checklist;
    _ = injector;

    var file = try std.Io.Dir.cwd().createFile(self.io, "broken.txt", .{});
    file.close(self.io);

    // Opening it works and reading it does not, which is what a disk giving out part way through a
    // read looks like to the code.
    try sim.filesystem.failReadsOf("broken.txt");

    var into: [16]u8 = undefined;
    const read = settings.setting(self.log, self.io, "broken.txt", &into);
    if (!std.mem.eql(u8, read, settings.fallback)) {
        return error.FallbackNotUsed;
    }
}

pub fn runEmptyFileScenario(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
    _ = checklist;
    _ = injector;

    var file = try std.Io.Dir.cwd().createFile(self.io, "empty.txt", .{});
    file.close(self.io);

    var into: [16]u8 = undefined;
    const read = settings.setting(self.log, self.io, "empty.txt", &into);
    if (!std.mem.eql(u8, read, settings.fallback)) {
        return error.FallbackNotUsed;
    }
}
