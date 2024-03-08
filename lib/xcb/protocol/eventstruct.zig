const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const EventStruct = @This();

name: []const u8,

pub fn deinit(self: *EventStruct, alloc: Allocator) void {
    alloc.free(self.name);
}

pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!void {
    var es = EventStruct{
        .name = blk: {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;
            break :blk try ev.attribute.dupeValue(self.allocator);
        },
    };
    errdefer es.deinit(self.allocator);

    try self.endParse(parser, "eventstruct");
    try self.eventstructs.append(self.allocator, es);
}
