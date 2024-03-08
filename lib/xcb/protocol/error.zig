const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const Field = @import("field.zig").Field;
const Error = @This();

name: []const u8,
number: isize,
fields: std.ArrayListUnmanaged(Field),

pub fn deinit(self: *Error, alloc: Allocator) void {
    alloc.free(self.name);

    for (self.fields.items) |field| field.deinit(alloc);
    self.fields.deinit(alloc);
}

pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!void {
    var err = Error{
        .name = blk: {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;
            break :blk try ev.attribute.dupeValue(self.allocator);
        },
        .number = blk: {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "number")) return error.UnknownAttribute;
            const value = try ev.attribute.dupeValue(self.allocator);
            defer self.allocator.free(value);
            break :blk try std.fmt.parseInt(isize, value, 10);
        },
        .fields = .{},
    };
    errdefer err.deinit(self.allocator);

    while (try Field.parse(self, parser)) |field| {
        errdefer field.deinit(self.allocator);
        try err.fields.append(self.allocator, field);
    }

    while (parser.next()) |ev| {
        if (ev == .close_tag) {
            if (std.mem.eql(u8, ev.close_tag, "error")) break;
        }
    }

    try self.errors.append(self.allocator, err);
}
