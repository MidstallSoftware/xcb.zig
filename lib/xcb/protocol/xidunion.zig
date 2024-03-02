const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const XidUnion = @This();

name: []const u8,
types: std.ArrayListUnmanaged([]const u8),

pub fn deinit(self: *XidUnion, alloc: Allocator) void {
    alloc.free(self.name);

    for (self.types.items) |name| alloc.free(name);
    self.types.deinit(alloc);
}

pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!void {
    var xidunion = XidUnion{
        .name = blk: {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;
            break :blk try ev.attribute.dupeValue(self.allocator);
        },
        .types = .{},
    };
    errdefer xidunion.deinit(self.allocator);

    while (parser.next()) |ev| switch (ev) {
        .open_tag => |tag| if (std.mem.eql(u8, tag, "type")) {
            const evValue = parser.next() orelse return error.UnexpectedEndOfFile;
            if (evValue != .character_data) return error.UnexpectedEvent;

            const value = try self.allocator.dupe(u8, evValue.character_data);
            errdefer self.allocator.free(value);

            try xidunion.types.append(self.allocator, value);
        },
        .close_tag => |tag| if (std.mem.eql(u8, tag, "xidunion")) break,
        else => {},
    };

    try self.xidunions.append(self.allocator, xidunion);
}
