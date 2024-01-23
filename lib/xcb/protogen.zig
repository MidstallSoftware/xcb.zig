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
        \\usingnamespace struct {
        \\  pub const CARD8 = u8;
        \\  pub const CARD16 = u16;
        \\  pub const CARD32 = u32;
        \\  pub const INT8 = i8;
        \\  pub const INT16 = i16;
        \\  pub const INT32 = i32;
        \\  pub const INT64 = i64;
        \\  pub const BYTE = u8;
        \\  pub const BOOL = u8;
        \\  pub const char = c_char;
        \\  pub const float = f32;
        \\  pub const double = f64;
        \\
    );

    for (doc.root.children) |child| {
        if (child != .element) continue;
        if (!std.mem.eql(u8, child.element.tag, "import")) continue;

        try outputFile.writer().print(
            \\  pub usingnamespace @import("{s}.zig");
            \\
        , .{child.element.children[0].char_data});
    }

    try outputFile.writer().writeAll("};");

    for (doc.root.children) |child| {
        if (child != .element) continue;

        const el = child.element;
        if (std.mem.eql(u8, el.tag, "request")) continue;

        const elName = el.getAttribute("name") orelse continue;

        try outputFile.writer().print("\npub const {s} = ", .{elName});

        if (std.mem.eql(u8, el.tag, "struct")) {
            try outputFile.writer().writeAll("struct {");

            for (el.children) |child2| {
                if (child2 != .element) continue;
                if (!std.mem.eql(u8, child2.element.tag, "field")) continue;

                const fieldName = child2.element.getAttribute("name") orelse continue;
                const fieldType = child2.element.getAttribute("type") orelse continue;

                try outputFile.writer().print(
                    \\  {s}: Self.{s},
                , .{ fieldName, fieldType });
            }

            try outputFile.writer().writeByte('}');
        } else if (std.mem.eql(u8, el.tag, "xidtype")) {
            try outputFile.writer().writeAll("u32");
        } else {
            try outputFile.writer().writeAll("opaque {}");
        }

        try outputFile.writer().writeAll(";\n");
    }
}
