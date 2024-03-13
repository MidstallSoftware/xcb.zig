const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    var screenId: c_int = 0;

    const conn = try xcb.Connection.connect(null, &screenId);
    defer conn.disconnect();

    const setup = conn.getSetup();
    const screen = blk: {
        var iter = setup.rootsIterator();
        var i: usize = 0;
        while (iter.next()) |screen| : (i += 1) {
            if (i == screenId) break :blk screen;
        }
        @panic("Cannot locate screen");
    };

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

    const win = xcb.xproto.WINDOW{ .value = try conn.generateId() };
    if (conn.requestCheck(xcb.xproto.createWindow(
        conn,
        screen.root_depth,
        win,
        screen.root,
        0,
        0,
        100,
        100,
        0,
        1,
        screen.root_visual,
        1 << xcb.xproto.CW.BackPixel | 1 << xcb.xproto.CW.EventMask,
        &[_]u32{ screen.black_pixel, 1 << 15 },
    ))) |_| return error.GenericError;

    if (conn.requestCheck(xcb.xproto.mapWindow(
        conn,
        win,
    ))) |_| return error.GenericError;

    try conn.flush();

    const pixmap = xcb.xproto.PIXMAP{ .value = try conn.generateId() };
    if (conn.requestCheck(xcb.xproto.createPixmap(
        conn,
        screen.root_depth,
        pixmap,
        .{ .window = win },
        100,
        100,
    ))) |_| return error.GenericError;

    const gc = xcb.xproto.GCONTEXT{ .value = try conn.generateId() };
    if (conn.requestCheck(xcb.xproto.createGC(
        conn,
        gc,
        .{ .pixmap = pixmap },
        1 << xcb.xproto.GC.Foreground | 1 << xcb.xproto.GC.Background,
        &[_]u32{ screen.black_pixel, screen.white_pixel },
    ))) |_| return error.GenericError;

    const fb = try alloc.alloc(u8, 100 * 100 * 4);
    defer alloc.free(fb);
    @memset(fb, 0xff);

    if (conn.requestCheck(xcb.xproto.putImage(
        conn,
        2,
        .{ .pixmap = pixmap },
        gc,
        100,
        100,
        0,
        0,
        screen.root_depth,
        0,
        0,
        fb.ptr,
    ))) |_| return error.GenericError;

    if (conn.requestCheck(xcb.xproto.copyArea(
        conn,
        .{ .pixmap = pixmap },
        .{ .window = win },
        gc,
        0,
        0,
        0,
        0,
        100,
        100,
    ))) |_| return error.GenericError;

    while (conn.waitForEvent() catch null) |ev| {
        if (ev.response_type == 12) {
            const exposeEvent: *xcb.xproto.events.Expose = @ptrCast(@alignCast(ev));
            std.debug.print("{}\n", .{exposeEvent});
        }
    }
}
