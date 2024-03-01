const std = @import("std");
const xml = @import("../deps/xml.zig");
const Self = @This();

step: std.Build.Step,
source: std.Build.LazyPath,
output: std.Build.GeneratedFile,

fn makeSnakeCase(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var upper: usize = 0;
    for (input) |ch| {
        if (std.ascii.isUpper(ch)) {
            upper += 1;
        }
    }

    var output = std.ArrayList(u8).init(alloc);
    errdefer output.deinit();

    for (input) |ch| {
        if (std.ascii.isUpper(ch) and upper != input.len) {
            try output.append('_');
            try output.append(std.ascii.toLower(ch));
        } else if (std.ascii.isUpper(ch) and upper == input.len) {
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

fn genStructFields(self: *Self, funcPrefix: []const u8, el: *xml.Element, elName: []const u8, structName: []const u8, writer: anytype) !void {
    const b = self.step.owner;
    const arena = b.allocator;

    const elNameSnakeName = try makeSnakeCase(arena, elName);
    defer arena.free(elNameSnakeName);

    for (el.children, 0..) |child, i| {
        if (child != .element) continue;
        const childElem = child.element;

        if (std.mem.eql(u8, childElem.tag, "pad")) {
            const bytes = try std.fmt.parseInt(usize, childElem.getAttribute("bytes") orelse continue, 10);
            if (bytes == 1 and i == 0) continue;

            try writer.print("         pad{}: [{}]u8,\n", .{ i, bytes });
        } else if (std.mem.eql(u8, childElem.tag, "field")) {
            const fieldName = childElem.getAttribute("name") orelse return error.AttributeNotFound;
            const fieldType = childElem.getAttribute("type") orelse return error.AttributeNotFound;

            try writer.print("         {s}: ", .{std.zig.fmtId(fieldName)});

            if (std.mem.indexOf(u8, fieldType, ":")) |x| {
                try writer.print("{s}.{s},\n", .{ fieldType[0..x], fieldType[(x + 1)..] });
            } else {
                try writer.print("Self.{s},\n", .{fieldType});
            }
        }
    }

    for (el.children) |child| {
        if (child != .element) continue;
        const childElem = child.element;

        if (std.mem.eql(u8, childElem.tag, "list")) {
            const fieldName = try arena.dupe(u8, childElem.getAttribute("name") orelse return error.AttributeNotFound);
            defer arena.free(fieldName);

            const fieldType = try arena.dupe(u8, childElem.getAttribute("type") orelse return error.AttributeNotFound);
            defer arena.free(fieldType);

            const snakeName = try makeSnakeCase(arena, fieldName);
            defer arena.free(snakeName);

            try writer.print("\nextern fn xcb{s}{s}_{s}_iterator(*const {s}) ", .{
                funcPrefix,
                elNameSnakeName,
                snakeName,
                structName,
            });

            if (std.mem.indexOf(u8, fieldType, ":")) |x| {
                try writer.print("{s}.{s}", .{ fieldType[0..x], fieldType[(x + 1)..] });
            } else {
                try writer.print("Self.{s}", .{fieldType});
            }

            try writer.print(
                \\.Iterator;
                \\pub const @"{c}{s}_iterator" = xcb{s}{s}_{s}_iterator;
                \\
                \\extern fn xcb{s}{s}_{s}_length(*const {s}) c_int;
                \\pub const @"{c}{s}_length" = xcb{s}{s}_{s}_length;
                \\
            , .{
                std.ascii.toLower(fieldName[0]),
                fieldName[1..],
                funcPrefix,
                elNameSnakeName,
                snakeName,
                funcPrefix,
                elNameSnakeName,
                snakeName,
                structName,
                std.ascii.toLower(fieldName[0]),
                fieldName[1..],
                funcPrefix,
                elNameSnakeName,
                snakeName,
            });
        }
    }
}

fn genRequest(self: *Self, funcPrefix: []const u8, el: *xml.Element, writer: anytype) !void {
    const b = self.step.owner;
    const arena = b.allocator;

    const elName = try arena.dupe(u8, el.getAttribute("name") orelse return error.AttributeNotFound);
    defer arena.free(elName);

    const snakeName = try makeSnakeCase(b.allocator, elName);
    defer b.allocator.free(snakeName);

    if (el.findChildByTag("reply")) |elReply| {
        try writer.print(
            \\
            \\pub const {s}Cookie = extern struct {{
            \\  seq: c_uint,
            \\
            \\  extern fn xcb{s}{s}_reply(*Connection, {s}Cookie, *?*connection.GenericError) ?*{s}Reply;
            \\  pub inline fn reply(self: {s}Cookie, conn: *Connection) !*{s}Reply {{
            \\      var err: ?*connection.GenericError = null;
            \\      const ret = xcb{s}{s}_reply(conn, self, &err);
            \\      if (err != null) {{
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
            funcPrefix,
            snakeName,
            elName,
            elName,
            elName,
            elName,
            funcPrefix,
            snakeName,
            elName,
        });

        try self.genStructFields(funcPrefix, elReply, elName, b.fmt("{s}Reply", .{elName}), writer);
    }

    try writer.print("\nextern fn xcb{s}{s}(*Connection", .{ funcPrefix, snakeName });

    var fieldIter = el.findChildrenByTag("field");
    while (fieldIter.next()) |fieldEl| {
        const fieldType = fieldEl.getAttribute("type") orelse return error.AttributeNotFound;
        if (std.mem.indexOf(u8, fieldType, ":")) |i| {
            try writer.print(", {s}.{s}", .{ fieldType[0..i], fieldType[(i + 1)..] });
        } else {
            try writer.print(", Self.{s}", .{fieldType});
        }
    }

    if (el.findChildByTag("reply")) |_| {
        try writer.print(") {s}Cookie;", .{elName});
    } else {
        try writer.writeAll(") connection.VoidCookie;");
    }

    try writer.print("\npub const @\"{c}{s}\" = xcb{s}{s};\n", .{ std.ascii.toLower(elName[0]), elName[1..], funcPrefix, snakeName });

    if (el.findChildByTag("reply")) |_| {
        try writer.writeAll("};\n");
    }
}

fn make(step: *std.Build.Step, _: *std.Progress.Node) !void {
    const b = step.owner;
    const self = @fieldParentPtr(Self, "step", step);

    var man = b.graph.cache.obtain();
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

    if (!std.mem.eql(u8, doc.root.tag, "xcb")) {
        return step.fail("not an xcb protocol, root tag is {s}, expected xcb", .{
            doc.root.tag,
        });
    }

    const funcPrefix = if (doc.root.getAttribute("extension-name")) |n| b.fmt("_{s}", .{try std.ascii.allocLowerString(b.allocator, n)}) else "";

    try outputFile.writer().writeAll(
        \\const std = @import("std");
        \\const connection = @import("../conn.zig");
        \\const Connection = connection.Connection;
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
        \\const {s} = struct {{
        \\
    , .{name[0..(name.len - 4)]});

    {
        var iter = doc.root.findChildrenByTag("xidtype");
        while (iter.next()) |el| {
            const fieldName = el.getAttribute("name") orelse return error.AttributeNotFound;

            try outputFile.writer().print(
                \\      pub const {s} = Self.CARD32;
                \\
            , .{fieldName});
        }
    }

    {
        var iter = doc.root.findChildrenByTag("typedef");
        while (iter.next()) |el| {
            const oldName = el.getAttribute("oldname") orelse return error.AttributeNotFound;
            const newName = el.getAttribute("newname") orelse return error.AttributeNotFound;

            try outputFile.writer().print(
                \\      pub const {s} = Self.{s};
                \\
            , .{ newName, oldName });
        }
    }

    {
        var iter = doc.root.findChildrenByTag("struct");
        while (iter.next()) |el| {
            const elName = try b.allocator.dupe(u8, el.getAttribute("name") orelse return error.AttributeNotFound);
            defer b.allocator.free(elName);

            const elNameSnakeName = try makeSnakeCase(b.allocator, elName);
            defer b.allocator.free(elNameSnakeName);

            try outputFile.writer().print("\npub const {s} = extern struct {{\n", .{elName});

            try self.genStructFields(funcPrefix, el, elName, elName, outputFile.writer());

            try outputFile.writer().print(
                \\pub const Iterator = extern struct {{
                \\  data: *const Self.{s},
                \\  rem: c_int,
                \\  index: c_int,
                \\
                \\  extern fn xcb{s}_{s}_next(*Iterator) void;
                \\
                \\  pub fn next(self: *Iterator) ?*const Self.{s} {{
                \\      if (self.rem == 0) return null;
                \\      const value = self.data;
                \\      xcb{s}_{s}_next(self);
                \\      return value;
                \\  }}
                \\}};
                \\}};
                \\
            , .{
                elName,
                funcPrefix,
                elNameSnakeName,
                elName,
                funcPrefix,
                elNameSnakeName,
            });
        }
    }

    {
        var iter = doc.root.findChildrenByTag("request");
        while (iter.next()) |el| {
            try self.genRequest(funcPrefix, el, outputFile.writer());
        }
    }

    try outputFile.writer().print(
        \\}};
        \\
        \\pub usingnamespace {s};
    , .{name[0..(name.len - 4)]});

    try step.writeManifest(&man);
}
