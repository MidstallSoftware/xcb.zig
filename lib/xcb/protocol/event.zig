const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const Field = @import("field.zig").Field;
const Event = @This();

name: []const u8,
number: usize,
fields: std.ArrayListUnmanaged(Field),
noSequenceNumber: ?bool,
xge: ?bool,

pub fn deinit(self: *Event, alloc: Allocator) void {
    alloc.free(self.name);

    for (self.fields.items) |field| field.deinit(alloc);
    self.fields.deinit(alloc);
}

pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!void {
    var event = Event{
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

            break :blk try std.fmt.parseInt(usize, value, 10);
        },
        .fields = .{},
        .noSequenceNumber = null,
        .xge = null,
    };
    errdefer event.deinit(self.allocator);

    {
        const doc = parser.document;
        const mode = parser.mode;

        const ev = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev == .attribute) {
            if (std.mem.eql(u8, ev.attribute.name, "no-sequence-number")) {
                const value = try ev.attribute.dupeValue(self.allocator);
                defer self.allocator.free(value);

                event.noSequenceNumber = std.mem.eql(u8, value, "true");
            } else if (std.mem.eql(u8, ev.attribute.name, "xge")) {
                const value = try ev.attribute.dupeValue(self.allocator);
                defer self.allocator.free(value);

                event.xge = std.mem.eql(u8, value, "true");
            } else return error.UnknownAttribute;
        } else {
            parser.document = doc;
            parser.mode = mode;
        }
    }

    while (try Field.parse(self, parser)) |field| {
        errdefer field.deinit(self.allocator);
        try event.fields.append(self.allocator, field);
    }

    while (parser.next()) |ev| {
        if (ev == .close_tag) {
            if (std.mem.eql(u8, ev.close_tag, "event")) break;
        }
    }

    try self.events.append(self.allocator, event);
}
