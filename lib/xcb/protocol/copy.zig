const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const Copy = @This();

pub const Kind = enum {
    event,
    @"error",
};

kind: Kind,
name: []const u8,
number: usize,
ref: []const u8,

pub fn deinit(self: *Copy, alloc: Allocator) void {
    alloc.free(self.name);
    alloc.free(self.ref);
}

pub fn parse(self: *Protocol, parser: *xml.Parser, kindStr: []const u8) Protocol.ParseError!void {
    const kind = std.meta.stringToEnum(Kind, kindStr) orelse return error.UnexpectedEvent;

    const name = blk: {
        const ev = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev != .attribute) return error.UnexpectedEvent;
        if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;
        break :blk try ev.attribute.dupeValue(self.allocator);
    };
    errdefer self.allocator.free(name);

    const number = blk: {
        const ev = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev != .attribute) return error.UnexpectedEvent;
        if (!std.mem.eql(u8, ev.attribute.name, "number")) return error.UnknownAttribute;

        const value = try ev.attribute.dupeValue(self.allocator);
        defer self.allocator.free(value);

        break :blk try std.fmt.parseInt(usize, value, 10);
    };

    const ref = blk: {
        const ev = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev != .attribute) return error.UnexpectedEvent;
        if (!std.mem.eql(u8, ev.attribute.name, "ref")) return error.UnknownAttribute;
        break :blk try ev.attribute.dupeValue(self.allocator);
    };
    errdefer self.allocator.free(ref);

    try self.copies.append(self.allocator, .{
        .kind = kind,
        .name = name,
        .number = number,
        .ref = ref,
    });
}

pub fn format(self: *const Copy, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    const width = (options.width orelse 0) + 2;

    try writer.writeAll(@typeName(Copy) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".kind = .");
    try std.zig.fmtId(@tagName(self.kind)).format(fmt, options, writer);
    try writer.writeAll(",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(self.name);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".number = ");
    try std.fmt.formatInt(self.number, 10, .lower, .{
        .width = 0,
        .fill = options.fill,
        .precision = options.precision,
        .alignment = options.alignment,
    }, writer);
    try writer.writeAll(",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".ref = \"");
    try writer.writeAll(self.ref);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}
