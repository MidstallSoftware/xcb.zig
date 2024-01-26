const std = @import("std");
const xml = @import("../deps/xml.zig");
const Self = @This();

step: std.Build.Step,
source: std.Build.LazyPath,
output: std.Build.GeneratedFile,

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
                \\
            , .{el.children[0].char_data});
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

    try outputFile.writer().print(
        \\}};
        \\
        \\pub usingnamespace {s};
    , .{name[0..(name.len - 4)]});
}
