const std = @import("std");
const xcb = @import("xcb");

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    _ = args.skip();

    const dirname = args.next() orelse {
        std.debug.print("Missing directory name\n", .{});
        std.process.exit(1);
    };

    var dir = if (std.fs.path.isAbsolute(dirname)) try std.fs.openDirAbsolute(dirname, .{ .iterate = true }) else try std.fs.cwd().openDir(dirname, .{ .iterate = true });
    defer dir.close();

    var walk = try dir.walk(alloc);
    defer walk.deinit();

    const stdout = std.io.getStdOut().writer();

    while (try walk.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.eql(u8, std.fs.path.extension(entry.basename), ".xml")) continue;

        var source = try entry.dir.openFile(entry.basename, .{});
        defer source.close();

        const protocol = try xcb.Protocol.create(alloc, .{
            .directory = dir,
            .source = source,
        });
        defer protocol.deinit();

        try stdout.print("{}\n", .{protocol});
    }
}
