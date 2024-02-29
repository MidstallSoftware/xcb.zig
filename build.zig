const std = @import("std");
const assert = std.debug.assert;

pub const ProtoGen = @import("lib/xcb/protogen.zig");

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
    child.env_map = &self.graph.env_map;
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
    const linkage = b.option(std.builtin.LinkMode, "linkage", "whether to statically or dynamically link the library") orelse @as(std.builtin.LinkMode, if (target.result.isGnuLibC()) .dynamic else .static);

    const libxcbSource = b.dependency("libxcb", .{});
    const xcbprotoSource = b.dependency("xcbproto", .{});

    const libxau = b.dependency("libxau", .{});
    const libxauSource = libxau.builder.dependency("libxau", .{});
    const xorgprotoSource = libxau.builder.dependency("xorgproto", .{});

    const xcbUtilSource = b.dependency("xcb-util", .{});
    const xcbUtilImageSource = b.dependency("xcb-util-image", .{});

    const python3 = try b.findProgram(&.{ "python3", "python" }, &.{});

    const headers = b.addWriteFiles();
    const moduleSource = b.addWriteFiles();

    const xcbprotoPath = blk: {
        var man = b.graph.cache.obtain();
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

        var protosImport = std.ArrayList(u8).init(b.allocator);
        defer protosImport.deinit();

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

                const header = b.fmt("{s}.h", .{entry.name[0..(entry.name.len - 4)]});

                _ = headers.addCopyFile(.{
                    .path = try std.fs.path.join(b.allocator, &.{ cachePath, header }),
                }, try std.fs.path.join(b.allocator, &.{ "xcb", header }));

                _ = moduleSource.addCopyFile(.{
                    .generated = &(ProtoGen.create(b, xcbprotoSource.path(try std.fs.path.join(b.allocator, &.{ "src", entry.name })))).output,
                }, try std.fs.path.join(b.allocator, &.{ "xcb", "proto", b.fmt("{s}.zig", .{entry.name[0..(entry.name.len - 4)]}) }));

                try protosImport.writer().print(
                    \\pub const {s} = @import("proto/{s}.zig");
                    \\
                , .{ entry.name[0..(entry.name.len - 4)], entry.name[0..(entry.name.len - 4)] });
            }

            try man.writeManifest();

            _ = moduleSource.add("xcb/protos.zig", protosImport.items);
            break :blk cachePath;
        } else {
            const digest = man.final();
            const cachePath = try b.cache_root.join(b.allocator, &.{ "o", &digest });

            iter = dir.iterate();
            while (try iter.next()) |entry| {
                if (!std.mem.endsWith(u8, entry.name, ".xml")) continue;

                const header = b.fmt("{s}.h", .{entry.name[0..(entry.name.len - 4)]});

                _ = headers.addCopyFile(.{
                    .path = try std.fs.path.join(b.allocator, &.{ cachePath, header }),
                }, try std.fs.path.join(b.allocator, &.{ "xcb", header }));

                _ = moduleSource.addCopyFile(.{
                    .generated = &(ProtoGen.create(b, xcbprotoSource.path(try std.fs.path.join(b.allocator, &.{ "src", entry.name })))).output,
                }, try std.fs.path.join(b.allocator, &.{ "xcb", "proto", b.fmt("{s}.zig", .{entry.name[0..(entry.name.len - 4)]}) }));
            }

            _ = moduleSource.add("xcb/protos.zig", protosImport.items);
            break :blk try b.cache_root.join(b.allocator, &.{ "o", &digest });
        }
    };

    {
        var dir = try std.fs.openDirAbsolute(xorgprotoSource.path("include").getPath(xorgprotoSource.builder), .{ .iterate = true });
        defer dir.close();

        var iter = try dir.walk(b.allocator);
        defer iter.deinit();

        while (try iter.next()) |entry| {
            if (std.mem.eql(u8, entry.basename, "meson.build")) continue;
            if (entry.kind != .file) continue;

            _ = headers.addCopyFile(xorgprotoSource.path(try std.fs.path.join(b.allocator, &.{ "include", entry.path })), entry.path);
        }
    }

    _ = headers.addCopyFile(libxcbSource.path("src/xcb.h"), "xcb/xcb.h");
    _ = headers.addCopyFile(xcbUtilSource.path("src/xcb_atom.h"), "xcb/xcb_atom.h");
    _ = headers.addCopyFile(xcbUtilSource.path("src/xcb_aux.h"), "xcb/xcb_aux.h");
    _ = headers.addCopyFile(xcbUtilSource.path("src/xcb_event.h"), "xcb/xcb_event.h");
    _ = headers.addCopyFile(xcbUtilSource.path("src/xcb_util.h"), "xcb/xcb_util.h");
    _ = headers.addCopyFile(xcbUtilImageSource.path("image/xcb_bitops.h"), "xcb/xcb_bitops.h");
    _ = headers.addCopyFile(xcbUtilImageSource.path("image/xcb_image.h"), "xcb/xcb_image.h");
    _ = headers.addCopyFile(xcbUtilImageSource.path("image/xcb_pixel.h"), "xcb/xcb_pixel.h");

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

    for (headers.files.items) |header| {
        const install_file = b.addInstallFileWithDir(header.getPath(), .header, header.sub_path);
        b.getInstallStep().dependOn(&install_file.step);
        libxcb.installed_headers.append(&install_file.step) catch @panic("OOM");
    }

    libxcb.addIncludePath(libxcbSource.path("src"));
    libxcb.addIncludePath(libxauSource.path("include"));
    libxcb.addIncludePath(xorgprotoSource.path("include"));
    libxcb.addIncludePath(.{ .path = xcbprotoPath });

    libxcb.addCSourceFiles(.{
        .root = libxcbSource.path("."),
        .files = &.{
            "src/xcb_auth.c",
            "src/xcb_conn.c",
            "src/xcb_ext.c",
            "src/xcb_in.c",
            "src/xcb_list.c",
            "src/xcb_out.c",
            "src/xcb_util.c",
            "src/xcb_xid.c",
        },
        .flags = &.{
            "-DXCB_QUEUE_BUFFER_SIZE=16384",
            "-DIOV_MAX=16",
        },
    });

    libxcb.addCSourceFiles(.{
        .root = .{ .path = xcbprotoPath },
        .files = &.{
            "bigreq.c",
            "xc_misc.c",
            "xproto.c",
        },
        .flags = &.{
            "-DXCB_QUEUE_BUFFER_SIZE=16384",
            "-DIOV_MAX=16",
        },
    });

    libxcb.linkLibrary(libxau.artifact("Xau"));
    b.installArtifact(libxcb);

    const libxcbShm = std.Build.Step.Compile.create(b, .{
        .name = "xcb-shm",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    libxcbShm.addIncludePath(libxcbSource.path("src"));
    libxcbShm.addIncludePath(libxauSource.path("include"));
    libxcbShm.addIncludePath(xorgprotoSource.path("include"));
    libxcbShm.addIncludePath(.{ .path = xcbprotoPath });

    libxcbShm.addCSourceFiles(.{
        .root = .{ .path = xcbprotoPath },
        .files = &.{"shm.c"},
    });

    libxcbShm.linkLibrary(libxcb);
    b.installArtifact(libxcbShm);

    const xcbutil = std.Build.Step.Compile.create(b, .{
        .name = "xcb-util",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    xcbutil.addIncludePath(headers.getDirectory());

    xcbutil.addCSourceFiles(.{
        .root = xcbUtilSource.path("src"),
        .files = &.{
            "atoms.c",
            "event.c",
            "xcb_aux.c",
        },
    });

    b.installArtifact(xcbutil);

    const xcbutilImage = std.Build.Step.Compile.create(b, .{
        .name = "xcb-image",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    xcbutilImage.addIncludePath(headers.getDirectory());

    xcbutilImage.addCSourceFiles(.{
        .root = xcbUtilImageSource.path("image"),
        .files = &.{
            "xcb_image.c",
        },
    });

    xcbutilImage.linkLibrary(xcbutil);
    xcbutilImage.linkLibrary(libxcbShm);
    b.installArtifact(xcbutilImage);

    {
        var dir = try std.fs.openDirAbsolute(b.pathFromRoot("lib"), .{ .iterate = true });
        defer dir.close();

        var iter = try dir.walk(b.allocator);
        defer iter.deinit();

        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (std.mem.eql(u8, entry.path, "xcb/protos.zig")) continue;

            _ = moduleSource.addCopyFile(.{
                .path = b.pathFromRoot(try std.fs.path.join(b.allocator, &.{ "lib", entry.path })),
            }, entry.path);
        }
    }

    const module = b.addModule("xcb", .{
        .root_source_file = blk: {
            for (moduleSource.files.items) |item| {
                if (std.mem.eql(u8, item.sub_path, "xcb.zig")) {
                    break :blk item.getPath();
                }
            }
            unreachable;
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    module.addIncludePath(headers.getDirectory());
    module.linkLibrary(libxcb);
    module.linkLibrary(xcbutilImage);

    const step_test = b.step("test", "Run all unit tests");

    const unit_tests = b.addTest(.{
        .root_source_file = module.root_source_file.?,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    unit_tests.addIncludePath(headers.getDirectory());
    unit_tests.linkLibrary(libxcb);
    unit_tests.linkLibrary(xcbutilImage);

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

    const example = b.addExecutable(.{
        .name = "example",
        .root_source_file = .{
            .path = b.pathFromRoot("example.zig"),
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .linkage = linkage,
    });

    example.root_module.addImport("xcb", module);
    b.installArtifact(example);
}
