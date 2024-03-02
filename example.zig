const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    const conn = try xcb.Connection.connect(null, null);
    defer conn.disconnect();

    const setup = conn.getSetup();
    std.debug.print("{}\n", .{setup});

    var iter = setup.rootsIterator();
    while (iter.next()) |screen| {
        const screenCount = try xcb.xinerama.getScreenCount(@ptrCast(@alignCast(conn)), screen.root).reply(@ptrCast(@alignCast(conn)));
        std.debug.print("{}\n", .{screenCount});
    }

    while (conn.waitForEvent() catch null) |ev| {
        std.debug.print("{}\n", .{ev});
    }
}
