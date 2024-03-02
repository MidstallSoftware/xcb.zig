const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const Field = @import("field.zig").Field;
const Union = @This();

name: []const u8,
fields: std.ArrayListUnmanaged(Field),

pub fn deinit(self: *Union, alloc: Allocator) void {
    alloc.free(self.name);

    for (self.fields.items) |field| field.deinit(alloc);
    self.fields.deinit(alloc);
}

pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!void {
    var str = Union{
        .name = blk: {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;
            break :blk try ev.attribute.dupeValue(self.allocator);
        },
        .fields = .{},
    };
    errdefer str.deinit(self.allocator);

    while (try Field.parse(self, parser)) |field| {
        errdefer field.deinit(self.allocator);
        try str.fields.append(self.allocator, field);
    }

    while (parser.next()) |ev| {
        if (ev == .close_tag) {
            if (std.mem.eql(u8, ev.close_tag, "union")) break;
        }
    }

    try self.unions.append(self.allocator, str);
}

pub fn format(self: *const Union, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    const width = (options.width orelse 0) + 2;

    try writer.writeAll(@typeName(Union) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(self.name);
    try writer.writeAll("\",\n");

    if (self.fields.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{\n");

        for (self.fields.items) |f| {
            try writer.writeByteNTimes(' ', width + 2);
            try f.format(fmt, .{
                .width = width + 2,
                .fill = options.fill,
                .precision = options.precision,
                .alignment = options.alignment,
            }, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{},\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}
