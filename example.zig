const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    const conn = try xcb.Connection.connect(null, null);
    defer conn.disconnect();

    const setup = conn.getSetup();
    std.debug.print("{}\n", .{setup});

    var iter = setup.rootsIterator();
    while (iter.next()) |screen| {
        const monitors = try xcb.randr.getMonitors(conn, screen.root, 0).reply(conn);
        var monitorsIter = monitors.monitorsIterator();

        while (monitorsIter.next()) |monitor| {
            std.debug.print("{} {}\n", .{ monitor, @sizeOf(@TypeOf(monitor)) });
            for (monitor.outputs()) |output| {
                const outputInfo = try xcb.randr.getOutputInfo(conn, output, 0).reply(conn);
                std.debug.print("{} {}\n", .{ outputInfo, @sizeOf(@TypeOf(outputInfo.*)) });

                const crtcInfo = try xcb.randr.getCrtcInfo(conn, outputInfo.crtc, 0).reply(conn);
                std.debug.print("{} {}\n", .{ crtcInfo, @sizeOf(@TypeOf(crtcInfo.*)) });
            }
        }
    }

    while (conn.waitForEvent() catch null) |ev| {
        std.debug.print("{}\n", .{ev});
    }
}
