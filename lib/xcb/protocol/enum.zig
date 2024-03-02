const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const Enum = @This();

pub const Item = struct {
    index: usize,
    bit: bool,

    pub fn format(self: *const Item, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        const width = (options.width orelse 0) + 2;

        try writer.writeAll(@typeName(Enum) ++ "{\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".index = ");
        try std.fmt.formatInt(self.index, 10, .lower, .{
            .alignment = options.alignment,
            .width = 0,
            .fill = options.fill,
            .precision = options.precision,
        }, writer);
        try writer.writeAll(",\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".bit = ");
        try writer.writeAll(if (self.bit) "true" else "false");
        try writer.writeAll(",\n");

        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeByte('}');
    }
};

name: []const u8,
items: std.StringHashMapUnmanaged(Item),

pub fn deinit(self: *Enum, alloc: Allocator) void {
    alloc.free(self.name);

    var iter = self.items.keyIterator();
    while (iter.next()) |key| alloc.free(key.*);
    self.items.deinit(alloc);
}

pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!void {
    var e = Enum{
        .name = blk: {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;
            break :blk try ev.attribute.dupeValue(self.allocator);
        },
        .items = .{},
    };
    errdefer e.deinit(self.allocator);

    while (parser.next()) |ev| switch (ev) {
        .open_tag => |tag| if (std.mem.eql(u8, tag, "item")) {
            try parseItem(self, parser, &e);
        },
        .close_tag => |tag| if (std.mem.eql(u8, tag, "enum")) break,
        else => {},
    };

    try self.enums.append(self.allocator, e);
}

fn parseItem(self: *Protocol, parser: *xml.Parser, e: *Enum) Protocol.ParseError!void {
    var value: ?usize = null;
    var name: ?[]const u8 = null;
    var isBit = false;

    while (parser.next()) |ev| switch (ev) {
        .open_tag => |tag| if (std.mem.eql(u8, tag, "value") or std.mem.eql(u8, tag, "bit")) {
            const evValue = parser.next() orelse return error.UnexpectedEndOfFile;
            if (evValue != .character_data) return error.UnexpectedEvent;
            value = try std.fmt.parseInt(usize, evValue.character_data, 10);
            isBit = std.mem.eql(u8, tag, "bit");
        },
        .attribute => |attr| if (std.mem.eql(u8, attr.name, "name")) {
            name = try attr.dupeValue(self.allocator);
        },
        .close_tag => |tag| if (std.mem.eql(u8, tag, "item")) break,
        else => {},
    };

    errdefer if (name) |v| self.allocator.free(v);
    if (value == null or name == null) return error.MissingNameOrVersion;
    try e.items.put(self.allocator, name.?, .{
        .index = value.?,
        .bit = isBit,
    });
}

pub fn format(self: *const Enum, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    const width = (options.width orelse 0) + 2;

    try writer.writeAll(@typeName(Enum) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(self.name);
    try writer.writeAll("\",\n");

    if (self.items.count() > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".items = .{\n");

        var iter = self.items.iterator();
        while (iter.next()) |item| {
            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeByte('.');
            try writer.writeAll(item.key_ptr.*);
            try writer.writeAll(" = ");
            try item.value_ptr.*.format(fmt, .{
                .alignment = options.alignment,
                .width = width + 2,
                .fill = options.fill,
                .precision = options.precision,
            }, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".items = .{},\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}
