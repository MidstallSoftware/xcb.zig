const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const Field = @import("field.zig").Field;
const Request = @This();

name: []const u8,
opcode: usize,
combineAdjacent: ?bool,
fields: std.ArrayListUnmanaged(Field),
reply: std.ArrayListUnmanaged(Field),

pub fn deinit(self: *Request, alloc: Allocator) void {
    alloc.free(self.name);

    for (self.fields.items) |field| field.deinit(alloc);
    self.fields.deinit(alloc);

    for (self.reply.items) |field| field.deinit(alloc);
    self.reply.deinit(alloc);
}

pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!void {
    var req = Request{
        .name = blk: {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;
            break :blk try ev.attribute.dupeValue(self.allocator);
        },
        .opcode = blk: {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "opcode")) return error.UnknownAttribute;

            const value = try ev.attribute.dupeValue(self.allocator);
            defer self.allocator.free(value);

            break :blk try std.fmt.parseInt(usize, value, 10);
        },
        .combineAdjacent = null,
        .fields = .{},
        .reply = .{},
    };
    errdefer req.deinit(self.allocator);

    {
        const doc = parser.document;
        const mode = parser.mode;

        const ev = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev == .attribute) {
            if (!std.mem.eql(u8, ev.attribute.name, "combine-adjacent")) return error.UnknownAttribute;

            const value = try ev.attribute.dupeValue(self.allocator);
            defer self.allocator.free(value);

            req.combineAdjacent = std.mem.eql(u8, value, "true");
        } else {
            parser.document = doc;
            parser.mode = mode;
        }
    }

    while (try Field.parse(self, parser)) |field| {
        errdefer field.deinit(self.allocator);
        try req.fields.append(self.allocator, field);
    }

    {
        const doc = parser.document;
        const mode = parser.mode;

        const ev = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev == .open_tag) {
            if (std.mem.eql(u8, ev.open_tag, "reply")) {
                while (try Field.parse(self, parser)) |field| {
                    errdefer field.deinit(self.allocator);
                    try req.reply.append(self.allocator, field);
                }
            } else {
                parser.document = doc;
                parser.mode = mode;
            }
        } else {
            parser.document = doc;
            parser.mode = mode;
        }
    }

    try self.endParse(parser, "request");
    try self.requests.append(self.allocator, req);
}
