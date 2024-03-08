const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    const conn = try xcb.Connection.connect(null, null);
    defer conn.disconnect();

    const setup = conn.getSetup();
    std.debug.print("{}\n", .{setup});

    var iter = setup.rootsIterator();
    while (iter.next()) |screen| {
        const monitors = try xcb.randr.getMonitors(@ptrCast(@alignCast(conn)), screen.root, 0).reply(@ptrCast(@alignCast(conn)));
        var monitorsIter = monitors.monitorsIterator();

        while (monitorsIter.next()) |monitor| {
            std.debug.print("{}\n", .{monitor});
            for (monitor.outputs()) |output| {
                std.debug.print("{}\n", .{output});
            }
        }
    }

    while (conn.waitForEvent() catch null) |ev| {
        std.debug.print("{}\n", .{ev});
    }
}
