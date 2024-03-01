const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    const conn = try xcb.Connection.connect(null, null);
    defer conn.disconnect();

    const setup = conn.getSetup();
    std.debug.print("{}\n", .{setup});

    var iter = setup.roots_iterator();
    while (iter.next()) |screen| std.debug.print("{}\n", .{screen});

    while (conn.waitForEvent() catch null) |ev| {
        std.debug.print("{}\n", .{ev});
    }
}
