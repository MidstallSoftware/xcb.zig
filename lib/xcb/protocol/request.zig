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
        const ev = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev == .open_tag) {
            if (std.mem.eql(u8, ev.open_tag, "reply")) {
                while (try Field.parse(self, parser)) |field| {
                    errdefer field.deinit(self.allocator);
                    try req.reply.append(self.allocator, field);
                }
            }
        }
    }

    while (parser.next()) |ev| {
        if (ev == .close_tag) {
            if (std.mem.eql(u8, ev.close_tag, "request")) break;
        }
    }

    try self.requests.append(self.allocator, req);
}

pub fn format(self: *const Request, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    const width = (options.width orelse 0) + 2;

    try writer.writeAll(@typeName(Request) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(self.name);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".opcode = ");
    try std.fmt.formatInt(self.opcode, 10, .lower, .{
        .width = 0,
        .fill = options.fill,
        .precision = options.precision,
        .alignment = options.alignment,
    }, writer);
    try writer.writeAll(",\n");

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

    if (self.reply.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".reply = .{\n");

        for (self.reply.items) |f| {
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
    }

    if (self.combineAdjacent) |combineAdjacent| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".combineAdjacent = ");
        try writer.writeAll(if (combineAdjacent) "true" else "false");
        try writer.writeAll(",\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}
