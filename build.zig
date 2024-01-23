const std = @import("std");
const assert = std.debug.assert;

fn runAllowFail(
    self: *std.Build,
    argv: []const []const u8,
    cwd: []const u8,
    out_code: *u8,
    stderr_behavior: std.ChildProcess.StdIo,
) std.Build.RunError![]u8 {
    assert(argv.len != 0);

    if (!std.process.can_spawn)
        return error.ExecNotSupported;

    const max_output_size = 400 * 1024;
    var child = std.ChildProcess.init(argv, self.allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = stderr_behavior;
    child.env_map = self.env_map;
    child.cwd = cwd;

    try child.spawn();

    const stdout = child.stdout.?.reader().readAllAlloc(self.allocator, max_output_size) catch {
        return error.ReadFailure;
    };
    errdefer self.allocator.free(stdout);

    const term = try child.wait();
    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                out_code.* = @as(u8, @truncate(code));
                return error.ExitCodeFailure;
            }
            return stdout;
        },
        .Signal, .Stopped, .Unknown => |code| {
            out_code.* = @as(u8, @truncate(code));
            return error.ProcessTerminated;
        },
    }
}

fn run(b: *std.Build, argv: []const []const u8, cwd: []const u8) []u8 {
    if (!std.process.can_spawn) {
        std.debug.print("unable to spawn the following command: cannot spawn child process\n{s}\n", .{
            try std.Build.Step.allocPrintCmd(b.allocator, null, argv),
        });
        std.process.exit(1);
    }

    var code: u8 = undefined;
    return runAllowFail(b, argv, cwd, &code, .Inherit) catch |err| {
        const printed_cmd = std.Build.Step.allocPrintCmd(b.allocator, null, argv) catch @panic("OOM");
        std.debug.print("unable to spawn the following command: {s}\n{s}\n", .{
            @errorName(err), printed_cmd,
        });
        std.process.exit(1);
    };
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_docs = b.option(bool, "no-docs", "skip installing documentation") orelse false;
    const linkage = b.option(std.Build.Step.Compile.Linkage, "linkage", "whether to statically or dynamically link the library") orelse .static;

    const libxcbSource = b.dependency("libxcb", .{});
    const xcbprotoSource = b.dependency("xcbproto", .{});

    const libxau = b.dependency("libxau", .{});
    const libxauSource = libxau.builder.dependency("libxau", .{});
    const xorgprotoSource = libxau.builder.dependency("xorgproto", .{});

    const python3 = try b.findProgram(&.{ "python3", "python" }, &.{});

    const xcbprotoPath = blk: {
        var man = b.cache.obtain();
        defer man.deinit();

        const xcbprotoSourcePath = xcbprotoSource.path("src").getPath(xcbprotoSource.builder);
        man.hash.addBytes(xcbprotoSourcePath);

        var dir = try std.fs.openDirAbsolute(xcbprotoSourcePath, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".xml")) continue;

            _ = try man.addFile(xcbprotoSource.path(try std.fs.path.join(b.allocator, &.{ "src", entry.name })).getPath(xcbprotoSource.builder), null);
        }

        if (!(try man.hit())) {
            const digest = man.final();
            const cachePath = try b.cache_root.join(b.allocator, &.{ "o", &digest });

            try b.cache_root.handle.makeDir(try std.fs.path.join(b.allocator, &.{ "o", &digest }));

            iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (!std.mem.endsWith(u8, entry.name, ".xml")) continue;

                _ = run(b, &.{
                    python3,
                    libxcbSource.path("src/c_client.py").getPath(xcbprotoSource.builder),
                    "-c",
                    "libxcb",
                    "-l",
                    "libxcb",
                    "-s",
                    "3",
                    "-p",
                    xcbprotoSource.path(".").getPath(xcbprotoSource.builder),
                    xcbprotoSource.path(try std.fs.path.join(b.allocator, &.{ "src", entry.name })).getPath(xcbprotoSource.builder),
                }, cachePath);
            }

            try man.writeManifest();

            break :blk cachePath;
        } else {
            const digest = man.final();
            break :blk try b.cache_root.join(b.allocator, &.{ "o", &digest });
        }
    };

    const libxcb = std.Build.Step.Compile.create(b, .{
        .name = "xcb",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    libxcb.addIncludePath(libxcbSource.path("src"));
    libxcb.addIncludePath(libxauSource.path("include"));
    libxcb.addIncludePath(xorgprotoSource.path("include"));
    libxcb.addIncludePath(.{ .path = xcbprotoPath });

    libxcb.addCSourceFiles(.{
        .files = &.{
            libxcbSource.path("src/xcb_auth.c").getPath(libxcbSource.builder),
            libxcbSource.path("src/xcb_conn.c").getPath(libxcbSource.builder),
            libxcbSource.path("src/xcb_ext.c").getPath(libxcbSource.builder),
            libxcbSource.path("src/xcb_in.c").getPath(libxcbSource.builder),
            libxcbSource.path("src/xcb_list.c").getPath(libxcbSource.builder),
            libxcbSource.path("src/xcb_out.c").getPath(libxcbSource.builder),
            libxcbSource.path("src/xcb_util.c").getPath(libxcbSource.builder),
            libxcbSource.path("src/xcb_xid.c").getPath(libxcbSource.builder),
            try std.fs.path.join(b.allocator, &.{ xcbprotoPath, "bigreq.c" }),
            try std.fs.path.join(b.allocator, &.{ xcbprotoPath, "xc_misc.c" }),
            try std.fs.path.join(b.allocator, &.{ xcbprotoPath, "xproto.c" }),
        },
        .flags = &.{
            "-DXCB_QUEUE_BUFFER_SIZE=16384",
            "-DIOV_MAX=16",
        },
    });

    libxcb.linkLibrary(libxau.artifact("Xau"));
    b.installArtifact(libxcb);

    const module = b.addModule("xcb", .{
        .root_source_file = .{
            .path = b.pathFromRoot("xcb.zig"),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    module.addIncludePath(libxcbSource.path("src"));
    module.addIncludePath(libxauSource.path("include"));
    module.addIncludePath(xorgprotoSource.path("include"));
    module.addIncludePath(.{ .path = xcbprotoPath });
    module.linkLibrary(libxcb);

    const step_test = b.step("test", "Run all unit tests");

    const unit_tests = b.addTest(.{
        .root_source_file = .{
            .path = b.pathFromRoot("xcb.zig"),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    unit_tests.addIncludePath(libxcbSource.path("src"));
    unit_tests.addIncludePath(libxauSource.path("include"));
    unit_tests.addIncludePath(xorgprotoSource.path("include"));
    unit_tests.addIncludePath(.{ .path = xcbprotoPath });
    unit_tests.linkLibrary(libxcb);

    const run_unit_tests = b.addRunArtifact(unit_tests);
    step_test.dependOn(&run_unit_tests.step);

    if (!no_docs) {
        const docs = b.addInstallDirectory(.{
            .source_dir = unit_tests.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });

        b.getInstallStep().dependOn(&docs.step);
    }
}
