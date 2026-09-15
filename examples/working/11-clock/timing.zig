// A function whose answer depends on time, exercised with the clock not moving, jumping forward, and
// jumping backward past where it started.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A clock the code under test reads, which is what a scenario moves rather than the real one.
pub const Clock = struct {
    now_ms: i64 = 0,

    pub fn now(self: *Clock) i64 {
        return self.now_ms;
    }
};

// Whether enough time has gone by. A clock that never moves, one that jumps forward and one that
// jumps backward each take a different side of this.
pub fn elapsed(log: Log, clock: *Clock, since_ms: i64, wanted_ms: i64) bool {
    const gone = clock.now() - since_ms;
    if (gone < 0) {
        if (an) annotate(log, "elapsed-went-backwards", "", .{});
        return false;
    } else {
        if (an) annotate(log, "elapsed-went-forwards", "", .{});
    }
    if (gone >= wanted_ms) {
        if (an) annotate(log, "elapsed-enough", "", .{});
        return true;
    } else {
        if (an) annotate(log, "elapsed-not-yet", "", .{});
    }
    return false;
}
