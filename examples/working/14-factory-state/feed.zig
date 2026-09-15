// A factory whose state has fields the run fills from their types, so one factory hands back a
// different value on every call.

const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

// A source of values, addressed as one dispatch point and a context beside it.
pub const Feed = struct {
    ctx: *anyopaque,
    next: *const fn (ctx: *anyopaque) ?u8,
};

// Adds up what the feed hands over until it runs dry.
pub fn total(log: Log, feed: Feed) usize {
    var sum: usize = 0;
    while (feed.next(feed.ctx)) |value| {
        if (an) annotate(log, "total-loop-iteration", "", .{});
        sum += value;
    }
    return sum;
}
