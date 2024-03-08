const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");
const Field = @import("field.zig").Field;
const Struct = @This();

name: []const u8,
fields: std.ArrayListUnmanaged(Field),

pub fn deinit(self: *Struct, alloc: Allocator) void {
    alloc.free(self.name);

    for (self.fields.items) |field| field.deinit(alloc);
    self.fields.deinit(alloc);
}

pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!void {
    var str = Struct{
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

    try self.endParse(parser, "struct");
    try self.structs.append(self.allocator, str);
}

test "Parsing xproto setup struct" {
    var parser = xml.Parser.init(
        \\<struct name="Setup">
        \\<field type="CARD8" name="status" /> <!-- always 1 -> Success -->
        \\<pad bytes="1" />
        \\<field type="CARD16" name="protocol_major_version" />
        \\<field type="CARD16" name="protocol_minor_version" />
        \\<field type="CARD16" name="length" />
        \\<field type="CARD32" name="release_number" />
        \\<field type="CARD32" name="resource_id_base" />
        \\<field type="CARD32" name="resource_id_mask" />
        \\<field type="CARD32" name="motion_buffer_size" />
        \\<field type="CARD16" name="vendor_len" />
        \\<field type="CARD16" name="maximum_request_length" />
        \\<field type="CARD8" name="roots_len" />
        \\<field type="CARD8" name="pixmap_formats_len" />
        \\<field type="CARD8" name="image_byte_order" enum="ImageOrder" />
        \\<field type="CARD8" name="bitmap_format_bit_order" enum="ImageOrder" />
        \\<field type="CARD8" name="bitmap_format_scanline_unit" />
        \\<field type="CARD8" name="bitmap_format_scanline_pad" />
        \\<field type="KEYCODE" name="min_keycode" />
        \\<field type="KEYCODE" name="max_keycode" />
        \\<pad bytes="4" />
        \\<list type="char" name="vendor">
        \\<fieldref>vendor_len</fieldref>
        \\</list>
        \\<pad align="4" />
        \\<list type="FORMAT" name="pixmap_formats">
        \\<fieldref>pixmap_formats_len</fieldref>
        \\</list>
        \\<list type="SCREEN" name="roots">
        \\<fieldref>roots_len</fieldref>
        \\</list>
        \\</struct>
    );

    const protocol = try std.testing.allocator.create(Protocol);
    protocol.* = .{
        .allocator = std.testing.allocator,
        .headerName = try std.testing.allocator.dupe(u8, "xproto"),
    };
    defer protocol.deinit();

    _ = parser.next();
    try parse(protocol, &parser);

    try std.testing.expectEqual(@as(usize, 1), protocol.structs.items.len);

    const self = protocol.structs.items[0];
    try std.testing.expectEqualStrings("Setup", self.name);
    try std.testing.expectEqual(@as(usize, 24), self.fields.items.len);
}
