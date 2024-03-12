const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const Enum = @This();

pub const Item = struct {
    index: usize,
    bit: bool,
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

pub fn min(self: *const Enum) usize {
    var i: usize = 0;
    var iter = self.items.valueIterator();
    while (iter.next()) |v| {
        if (v.index < i) i = v.index;
    }
    return i;
}

pub fn max(self: *const Enum) usize {
    var i: usize = 0;
    var iter = self.items.valueIterator();
    while (iter.next()) |v| {
        if (v.index > i) i = v.index;
    }
    return i;
}

pub fn isBits(self: *const Enum) bool {
    var iter = self.items.valueIterator();
    while (iter.next()) |v| {
        if (!v.bit) return false;
    }
    return true;
}
