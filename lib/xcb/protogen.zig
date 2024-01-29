const std = @import("std");
const xml = @import("../deps/xml.zig");
const Self = @This();

step: std.Build.Step,
source: std.Build.LazyPath,
output: std.Build.GeneratedFile,

fn makeSnakeCase(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var output = std.ArrayList(u8).init(alloc);
    errdefer output.deinit();

    for (input) |ch| {
        if (std.ascii.isUpper(ch)) {
            try output.append('_');
            try output.append(std.ascii.toLower(ch));
        } else {
            try output.append(ch);
        }
    }
    return try output.toOwnedSlice();
}

pub fn create(b: *std.Build, source: std.Build.LazyPath) *Self {
    const self = b.allocator.create(Self) catch @panic("OOM");
    errdefer b.allocator.destroy(self);

    self.* = .{
        .step = std.Build.Step.init(.{
            .id = .custom,
            .name = b.fmt("xcb protocol generation {s}", .{source.getDisplayName()}),
            .owner = b,
            .makeFn = make,
        }),
        .source = source,
        .output = .{ .step = &self.step },
    };

    source.addStepDependencies(&self.step);
    return self;
}

fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
    const b = step.owner;
    const self = @fieldParentPtr(Self, "step", step);

    var man = b.cache.obtain();
    defer man.deinit();

    const path = self.source.getPath2(b, step);
    const name = blk: {
        const temp = std.fs.path.basename(path);
        break :blk b.fmt("{s}.zig", .{temp[0..(temp.len - 4)]});
    };

    self.step.name = b.fmt("xcb protocol generation {s}", .{std.fs.path.basename(path)});

    _ = try man.addFile(path, null);

    if (try step.cacheHit(&man)) {
        const digest = man.final();
        self.output.path = try b.cache_root.join(b.allocator, &.{ "o", &digest, name });
        return;
    }

    const digest = man.final();
    self.output.path = try b.cache_root.join(b.allocator, &.{ "o", &digest, name });

    var sourceFile = try std.fs.openFileAbsolute(path, .{});
    defer sourceFile.close();

    const metadata = try sourceFile.metadata();

    var source = try sourceFile.readToEndAlloc(b.allocator, metadata.size());
    defer b.allocator.free(source);

    while (std.mem.indexOf(u8, source, "<![CDATA[")) |i| {
        const x = std.mem.indexOf(u8, source, "]]>") orelse return error.UnmatchedCData;

        const oldsource = source;
        source = b.fmt("{s}{s}", .{ source[0..i], source[(x + 3)..] });
        b.allocator.free(oldsource);
    }

    const doc = xml.parse(b.allocator, source) catch |err| {
        return step.fail("unable to parse '{s}': {s}", .{
            path,
            @errorName(err),
        });
    };
    defer doc.deinit();

    const cache_path = try std.fs.path.join(b.allocator, &.{ "o", &digest });

    var cache_dir = b.cache_root.handle.makeOpenPath(cache_path, .{}) catch |err| {
        return step.fail("unable to make path '{}{s}': {s}", .{
            b.cache_root, cache_path, @errorName(err),
        });
    };
    defer cache_dir.close();

    var outputFile = try cache_dir.createFile(name, .{});
    defer outputFile.close();

    errdefer std.debug.print("{s}/{s}\n", .{ cache_path, name });

    if (!std.mem.eql(u8, doc.root.tag, "xcb")) {
        return step.fail("not an xcb protocol, root tag is {s}, expected xcb", .{
            doc.root.tag,
        });
    }

    try outputFile.writer().writeAll(
        \\const conn = @import("../conn.zig");
        \\const Connection = conn.Connection;
        \\const Self = @This();
        \\
        \\const CARD8 = u8;
        \\const CARD16 = u16;
        \\const CARD32 = u32;
        \\const INT8 = i8;
        \\const INT16 = i16;
        \\const INT32 = i32;
        \\const INT64 = i64;
        \\const BYTE = u8;
        \\const BOOL = u8;
        \\const char = c_char;
        \\const float = f32;
        \\const double = f64;
        \\
        \\
    );

    {
        var iter = doc.root.findChildrenByTag("import");
        while (iter.next()) |el| {
            try outputFile.writer().print(
                \\usingnamespace @import("{s}.zig");
                \\pub const {s} = @import("{s}.zig");
                \\
            , .{ el.children[0].char_data, el.children[0].char_data, el.children[0].char_data });
        }
    }

    try outputFile.writer().print(
        \\
        \\  const {s} = struct {{
        \\
    , .{name[0..(name.len - 4)]});

    {
        var iter = doc.root.findChildrenByTag("typedef");
        while (iter.next()) |el| {
            const oldName = el.getAttribute("oldname") orelse return error.AttributeNotFound;
            const newName = el.getAttribute("newname") orelse return error.AttributeNotFound;

            try outputFile.writer().print(
                \\      const {s} = Self.{s};
                \\
            , .{ newName, oldName });
        }
    }

    {
        var iter = doc.root.findChildrenByTag("struct");
        while (iter.next()) |el| {
            const elName = el.getAttribute("name") orelse return error.AttributeNotFound;
            try outputFile.writer().print("\npub const {s} = extern struct {{\n", .{elName});

            var fieldIter = el.findChildrenByTag("field");
            while (fieldIter.next()) |fieldEl| {
                const fieldName = fieldEl.getAttribute("name") orelse return error.AttributeNotFound;
                const fieldType = fieldEl.getAttribute("type") orelse return error.AttributeNotFound;

                try outputFile.writer().print("         {s}: ", .{fieldName});

                if (std.mem.indexOf(u8, fieldType, ":")) |i| {
                    try outputFile.writer().print("{s}.{s},\n", .{ fieldType[0..i], fieldType[(i + 1)..] });
                } else {
                    try outputFile.writer().print("Self.{s},\n", .{fieldType});
                }
            }

            try outputFile.writer().writeAll("};\n");
        }
    }

    {
        var iter = doc.root.findChildrenByTag("request");
        while (iter.next()) |el| {
            const elName = el.getAttribute("name") orelse return error.AttributeNotFound;
            const snakeName = try makeSnakeCase(b.allocator, elName);
            defer b.allocator.free(snakeName);

            if (el.findChildByTag("reply")) |elReply| {
                try outputFile.writer().print(
                    \\
                    \\pub const {s}Cookie = extern struct {{
                    \\  seq: c_uint,
                    \\
                    \\  extern fn xcb{s}_reply(*Connection, {s}Cookie, *?*conn.GenericError) ?*{s}Reply;
                    \\  pub inline fn reply(self: {s}Cookie, conn: *Connection) !*{s}Reply {{
                    \\      var err: ?*conn.GenericError = null;
                    \\      const ret = xcb{s}_reply(conn, self, &err);
                    \\      if (err == null) {{
                    \\          std.debug.assert(ret == null);
                    \\          return error.GenericError;
                    \\      }}
                    \\
                    \\      std.debug.assert(ret != null);
                    \\      return ret.?;
                    \\  }}
                    \\}};
                    \\
                    \\pub const {s}Reply = extern struct {{
                    \\  response_type: u8,
                    \\  pad0: u8,
                    \\  seq: u16,
                    \\  len: u32,
                    \\
                , .{
                    elName,
                    snakeName,
                    elName,
                    elName,
                    elName,
                    elName,
                    snakeName,
                    elName,
                });

                for (elReply.children, 0..) |elReplyChild, i| {
                    if (elReplyChild != .element) continue;

                    const elReplyChildEl = elReplyChild.element;
                    if (std.mem.eql(u8, elReplyChildEl.tag, "pad")) {
                        const bytes = try std.fmt.parseInt(usize, elReplyChildEl.getAttribute("bytes") orelse continue, 10);
                        if (bytes == 1 and i == 0) continue;

                        try outputFile.writer().print("pad{}: [{}]u8", .{ i, bytes });
                    } else if (std.mem.eql(u8, elReplyChildEl.tag, "field")) {
                        const fieldName = elReplyChildEl.getAttribute("name") orelse return error.AttributeNotFound;
                        const fieldType = elReplyChildEl.getAttribute("type") orelse return error.AttributeNotFound;

                        try outputFile.writer().print("         {s}: ", .{fieldName});

                        if (std.mem.indexOf(u8, fieldType, ":")) |x| {
                            try outputFile.writer().print("{s}.{s},\n", .{ fieldType[0..x], fieldType[(x + 1)..] });
                        } else {
                            try outputFile.writer().print("Self.{s},\n", .{fieldType});
                        }
                    }
                }
            }

            try outputFile.writer().print("\n}};\nextern fn xcb{s}(*Connection", .{snakeName});

            var fieldIter = el.findChildrenByTag("field");
            while (fieldIter.next()) |fieldEl| {
                const fieldType = fieldEl.getAttribute("type") orelse return error.AttributeNotFound;
                if (std.mem.indexOf(u8, fieldType, ":")) |i| {
                    try outputFile.writer().print(", {s}.{s}", .{ fieldType[0..i], fieldType[(i + 1)..] });
                } else {
                    try outputFile.writer().print(", Self.{s}", .{fieldType});
                }
            }

            if (el.findChildByTag("reply")) |_| {
                try outputFile.writer().print(") {s}Cookie;", .{elName});
            } else {
                try outputFile.writer().writeAll(") conn.VoidCookie;");
            }

            try outputFile.writer().print("\npub const @\"{c}{s}\" = xcb{s};\n", .{ std.ascii.toLower(elName[0]), elName[1..], snakeName });
        }
    }

    try outputFile.writer().print(
        \\}};
        \\
        \\pub usingnamespace {s};
    , .{name[0..(name.len - 4)]});
}
