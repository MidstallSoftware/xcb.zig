const std = @import("std");
const clap = @import("clap");
const xcb = @import("xcb");

const parsers = .{
    .dir = (struct {
        fn func(in: []const u8) !std.fs.Dir {
            return if (std.fs.path.isAbsolute(in)) try std.fs.openDirAbsolute(in, .{ .iterate = true }) else try std.fs.cwd().openDir(in, .{ .iterate = true });
        }
    }).func,
    .gen = clap.parsers.enumeration(std.meta.DeclEnum(xcb.Protocol.generators)),
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const params = comptime clap.parseParamsComptime(
        \\-h, --help            Display this help and exit.
        \\-g, --generator <gen> Renders the scanned protocols in a particular format.
        \\<dir>                 The directory to scan.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = alloc,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.positionals.len != 1 or res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    }

    var dir = res.positionals[0];
    defer dir.close();

    var walk = try dir.walk(alloc);
    defer walk.deinit();

    const stdout = std.io.getStdOut().writer();

    var list = std.ArrayList(*xcb.Protocol).init(alloc);
    defer {
        for (list.items) |item| item.deinit();
        list.deinit();
    }

    while (try walk.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.eql(u8, std.fs.path.extension(entry.basename), ".xml")) continue;

        var source = try entry.dir.openFile(entry.basename, .{});
        defer source.close();

        const protocol = xcb.Protocol.create(alloc, .{
            .directory = res.positionals[0],
            .source = source,
        }) catch |err| {
            std.debug.print("Failed to generate protocol file {s}\n", .{entry.basename});
            return err;
        };
        errdefer protocol.deinit();

        try list.append(protocol);
    }

    try stdout.print("{}\n", .{xcb.Protocol.generateSet(list.items, res.args.generator orelse .zon)});
}
