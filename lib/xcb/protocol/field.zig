const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../../xml.zig");
const Protocol = @import("../protocol.zig");

pub const EnumRef = struct {
    ref: []const u8,
    type: []const u8,

    pub fn deinit(self: *const EnumRef, alloc: Allocator) void {
        alloc.free(self.ref);
        alloc.free(self.type);
    }

    pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!EnumRef {
        const ev1 = parser.next() orelse error.UnexpectedEndOfFile;
        if (ev1 != .attribute) return error.UnexpectedEvent;
        if (!std.mem.eql(u8, ev1.attribute.name, "ref")) return error.UnknownAttribute;

        const ev2 = parser.next() orelse error.UnexpectedEndOfFile;
        if (ev2 != .character_data) return error.UnexpectedEvent;

        return .{
            .ref = try ev1.attribute.dupeValue(self.allocator),
            .type = try self.allocator.dupe(u8, ev2.character_data),
        };
    }

    pub fn format(self: *EnumRef, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        const width = (options.width orelse 0) + 2;

        try writer.writeAll(@typeName(EnumRef) ++ "{\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".ref = \"");
        try writer.writeAll(self.ref);
        try writer.writeAll("\",\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".type = \"");
        try writer.writeAll(self.type);
        try writer.writeAll("\",\n");

        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeByte('}');
    }
};

pub const NamedValue = struct {
    name: []const u8,
    value: *Value,

    pub fn deinit(self: *NamedValue, alloc: Allocator) void {
        alloc.free(self.name);
        self.value.deinit(alloc);
        alloc.destroy(self.value);
    }

    pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!NamedValue {
        const ev1 = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev1 != .attribute) return error.UnexpectedEvent;
        if (!std.mem.eql(u8, ev1.attribute.name, "name")) return error.UnknownAttribute;

        const name = try ev1.attribute.dupeValue(self.allocator);
        errdefer self.allocator.free(name);

        var value = try self.allocator.create(Value);
        errdefer self.allocator.destroy(value);

        value.* = try Value.parse(self, parser) orelse return error.UnexpectedEndOfFile;
        errdefer value.deinit(self.allocator);

        return .{
            .name = name,
            .value = value,
        };
    }

    pub fn format(self: *NamedValue, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        const width = (options.width orelse 0) + 2;

        try writer.writeAll(@typeName(NamedValue) ++ "{\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".name = \"");
        try writer.writeAll(self.name);
        try writer.writeAll("\",\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".name = \"");
        try self.value.format(fmt, .{
            .width = width,
            .fill = options.fill,
            .precision = options.precision,
            .alignment = options.alignment,
        }, writer);
        try writer.writeAll(",\n");

        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeByte('}');
    }
};

pub const Value = union(enum) {
    fieldref: []const u8,
    value: usize,
    op: Op,
    unop: Op,
    popcount: *Value,
    field: Field.Default,
    pad: Field.Pad,
    list: Field.List,
    enumref: EnumRef,
    bitcase: NamedValue,
    @"switch": NamedValue,

    pub fn deinit(self: *Value, alloc: Allocator) void {
        switch (self.*) {
            .fieldref => |fieldref| alloc.free(fieldref),
            .op, .unop => |*op| op.deinit(alloc),
            .popcount => |popcount| popcount.deinit(alloc),
            .bitcase, .@"switch" => |*nv| nv.deinit(alloc),
            .field => |field| field.deinit(alloc),
            .list => |*list| list.deinit(alloc),
            .enumref => |ef| ef.deinit(alloc),
            else => {},
        }
    }

    pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!?Value {
        const kind = blk: {
            while (true) {
                const document = parser.document;
                const mode = parser.mode;

                const v = parser.next() orelse break;

                switch (v) {
                    .comment => continue,
                    .close_tag => |t| {
                        if (std.meta.stringToEnum(std.meta.Tag(Value), t) == null) {
                            parser.document = document;
                            parser.mode = mode;
                            return null;
                        }
                        continue;
                    },
                    .open_tag => break :blk std.meta.stringToEnum(std.meta.Tag(Value), v.open_tag) orelse {
                        parser.document = document;
                        parser.mode = mode;
                        return null;
                    },
                    else => {
                        std.debug.print("{}\n", .{v});
                        return error.UnexpectedEvent;
                    },
                }
            }
            return error.UnexpectedEndOfFile;
        };

        return switch (kind) {
            .field => .{ .field = try Field.Default.parse(self, parser) },
            .pad => .{ .pad = try Field.Pad.parse(self, parser) },
            .list => .{ .list = try Field.List.parse(self, parser) },
            inline .op, .unop => |v| @unionInit(Value, @tagName(v), try Op.parse(self, parser)),
            inline .@"switch", .bitcase => |v| @unionInit(Value, @tagName(v), try NamedValue.parse(self, parser)),
            inline .popcount => |v| blk: {
                const value = try self.allocator.create(Value);
                errdefer self.allocator.destroy(value);

                value.* = try parse(self, parser) orelse return error.UnexpectedEndOfFile;
                errdefer value.deinit(self.allocator);

                break :blk @unionInit(Value, @tagName(v), value);
            },
            inline else => blk: {
                const ev2 = parser.next() orelse return error.UnexpectedEndOfFile;
                if (ev2 != .character_data) return error.UnexpectedEvent;

                const valueStr = try self.allocator.dupe(u8, ev2.character_data);
                errdefer self.allocator.free(valueStr);

                break :blk switch (kind) {
                    .op, .unop, .popcount, .field, .pad, .list, .@"switch", .bitcase, .enumref => unreachable,
                    inline .value => |v| @unionInit(Value, @tagName(v), try std.fmt.parseInt(usize, valueStr, 10)),
                    inline else => |k| @unionInit(Value, @tagName(k), valueStr),
                };
            },
        };
    }

    pub fn format(self: *Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        const width = (options.width orelse 0) + 2;

        try writer.writeAll(@typeName(Value) ++ "{\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeByte('.');
        try writer.writeAll(@tagName(std.meta.activeTag(self.*)));
        try writer.writeAll(" = ");

        switch (self.*) {
            .value => |v| try std.fmt.formatInt(v, 10, .lower, .{
                .width = 0,
                .fill = options.fill,
                .precision = options.precision,
                .alignment = options.alignment,
            }, writer),
            .fieldref => |v| {
                try writer.writeByte('"');
                try writer.writeAll(v);
                try writer.writeByte('"');
            },
            .popcount => |v| try format(v, fmt, .{
                .width = width,
                .fill = options.fill,
                .precision = options.precision,
                .alignment = options.alignment,
            }, writer),
            inline else => |*v| try v.format(fmt, .{
                .width = width,
                .fill = options.fill,
                .precision = options.precision,
                .alignment = options.alignment,
            }, writer),
        }

        try writer.writeAll(",\n");
        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeByte('}');
    }
};

pub const Op = struct {
    pub const Kind = enum {
        @"*",
        @"/",
        @"-",
        @"+",
        @"&",
        @"~",
    };

    kind: Kind,
    values: std.ArrayListUnmanaged(Value),

    pub fn deinit(self: *Op, alloc: Allocator) void {
        for (self.values.items) |*value| value.deinit(alloc);
        self.values.deinit(alloc);
    }

    pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!Op {
        const ev = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev != .attribute) return error.UnexpectedEvent;
        if (!std.mem.eql(u8, ev.attribute.name, "op")) return error.UnknownAttribute;

        const kindValue = try ev.attribute.dupeValue(self.allocator);
        defer self.allocator.free(kindValue);

        const kind = std.meta.stringToEnum(Kind, kindValue) orelse return error.UnknownAttribute;

        var op = Op{
            .kind = kind,
            .values = .{},
        };
        errdefer op.deinit(self.allocator);

        while (try Value.parse(self, parser)) |value| {
            errdefer @constCast(&value).deinit(self.allocator);
            try op.values.append(self.allocator, value);
        }
        return op;
    }

    pub fn format(self: *const Op, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) @TypeOf(writer).Error!void {
        const width = (options.width orelse 0) + 2;

        try writer.writeAll(@typeName(Op) ++ "{\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".kind = ");
        try std.zig.fmtId(@tagName(self.kind)).format(fmt, options, writer);
        try writer.writeAll(",\n");

        if (self.values.items.len > 0) {
            try writer.writeByteNTimes(' ', width);
            try writer.writeAll(".values = .{\n");

            for (self.values.items) |*value| {
                try writer.writeByteNTimes(' ', width + 2);
                try value.format(fmt, .{
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
            try writer.writeAll(".values = .{},\n");
        }

        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeByte('}');
    }
};

pub const Field = union(enum) {
    field: Default,
    pad: Pad,
    list: List,

    pub const Default = struct {
        type: []const u8,
        name: []const u8,
        mask: ?[]const u8,
        @"enum": ?[]const u8,

        pub fn deinit(self: Default, alloc: Allocator) void {
            alloc.free(self.type);
            alloc.free(self.name);
        }

        pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!Default {
            const ev1 = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev1 != .attribute) return error.UnexpectedEvent;

            const ev2 = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev2 != .attribute) return error.UnexpectedEvent;

            const ev3 = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev3 != .attribute and ev3 != .close_tag) return error.UnexpectedEvent;

            if (std.mem.eql(u8, ev1.attribute.name, ev2.attribute.name)) return error.DuplicateAttributes;

            const typename = if (std.mem.eql(u8, ev1.attribute.name, "type")) ev1.attribute else ev2.attribute;
            const name = if (std.mem.eql(u8, ev2.attribute.name, "name")) ev2.attribute else ev1.attribute;

            std.debug.assert(std.mem.eql(u8, typename.name, "type"));
            std.debug.assert(std.mem.eql(u8, name.name, "name"));

            const typenameValue = try typename.dupeValue(self.allocator);
            errdefer self.allocator.free(typenameValue);

            const nameValue = try name.dupeValue(self.allocator);
            errdefer self.allocator.free(nameValue);

            var field = Default{
                .type = typenameValue,
                .name = nameValue,
                .mask = null,
                .@"enum" = null,
            };

            if (ev3 == .attribute) {
                if (std.mem.eql(u8, ev3.attribute.name, "mask")) {
                    field.mask = try ev3.attribute.dupeValue(self.allocator);
                } else if (std.mem.eql(u8, ev3.attribute.name, "enum")) {
                    field.@"enum" = try ev3.attribute.dupeValue(self.allocator);
                }
            }
            return field;
        }

        pub fn format(self: *const Default, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            const width = (options.width orelse 0) + 2;

            try writer.writeAll(@typeName(Default) ++ "{\n");

            try writer.writeByteNTimes(' ', width);
            try writer.writeAll(".type = \"");
            try writer.writeAll(self.type);
            try writer.writeAll("\",\n");

            try writer.writeByteNTimes(' ', width);
            try writer.writeAll(".name = \"");
            try writer.writeAll(self.name);
            try writer.writeAll("\",\n");

            if (self.mask) |mask| {
                try writer.writeByteNTimes(' ', width);
                try writer.writeAll(".mask = \"");
                try writer.writeAll(mask);
                try writer.writeAll("\",\n");
            }

            if (self.@"enum") |e| {
                try writer.writeByteNTimes(' ', width);
                try writer.writeAll(".@\"enum\" = \"");
                try writer.writeAll(e);
                try writer.writeAll("\",\n");
            }

            try writer.writeByteNTimes(' ', width - 2);
            try writer.writeByte('}');
        }
    };

    pub const Pad = union(enum) {
        bytes: usize,
        @"align": usize,

        pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!Pad {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;

            const kind = std.meta.stringToEnum(std.meta.Tag(Pad), ev.attribute.name) orelse return error.UnknownAttribute;

            const valueStr = try ev.attribute.dupeValue(self.allocator);
            defer self.allocator.free(valueStr);

            const value = try std.fmt.parseInt(usize, valueStr, 10);

            inline for (comptime std.meta.fields(std.meta.Tag(Pad))) |field| {
                if (field.value == @intFromEnum(kind)) {
                    return @unionInit(Pad, field.name, value);
                }
            }
            unreachable;
        }

        pub fn format(self: *const Pad, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            const width = (options.width orelse 0) + 2;

            try writer.writeAll(@typeName(Pad) ++ "{\n");

            try writer.writeByteNTimes(' ', width);
            try writer.writeByte('.');
            try writer.writeAll(@tagName(std.meta.activeTag(self.*)));
            try writer.writeAll(" = ");

            switch (self.*) {
                inline else => |v| try std.fmt.formatInt(v, 10, .lower, .{
                    .width = 0,
                    .fill = options.fill,
                    .precision = options.precision,
                    .alignment = options.alignment,
                }, writer),
            }

            try writer.writeAll(",\n");
            try writer.writeByteNTimes(' ', width - 2);
            try writer.writeByte('}');
        }
    };

    pub const List = struct {
        type: []const u8,
        name: []const u8,
        values: std.ArrayListUnmanaged(Value),
        mask: ?[]const u8,
        @"enum": ?[]const u8,

        pub fn deinit(self: *List, alloc: Allocator) void {
            alloc.free(self.type);
            alloc.free(self.name);

            for (self.values.items) |*value| value.deinit(alloc);
            self.values.deinit(alloc);
        }

        pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!List {
            const ev1 = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev1 != .attribute) return error.UnexpectedEvent;

            const ev2 = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev2 != .attribute) return error.UnexpectedEvent;

            const document = parser.document;
            const mode = parser.mode;

            const ev3 = parser.next() orelse return error.UnexpectedEndOfFile;

            if (std.mem.eql(u8, ev1.attribute.name, ev2.attribute.name)) return error.DuplicateAttributes;

            const typename = if (std.mem.eql(u8, ev1.attribute.name, "type")) ev1.attribute else ev2.attribute;
            const name = if (std.mem.eql(u8, ev2.attribute.name, "name")) ev2.attribute else ev1.attribute;

            std.debug.assert(std.mem.eql(u8, typename.name, "type"));
            std.debug.assert(std.mem.eql(u8, name.name, "name"));

            const typenameValue = try typename.dupeValue(self.allocator);
            const nameValue = try name.dupeValue(self.allocator);

            if (ev3 == .open_tag) {
                parser.document = document;
                parser.mode = mode;
            }

            var list = List{
                .type = typenameValue,
                .name = nameValue,
                .values = .{},
                .mask = null,
                .@"enum" = null,
            };
            errdefer list.deinit(self.allocator);

            while (try Value.parse(self, parser)) |value| {
                errdefer @constCast(&value).deinit(self.allocator);
                try list.values.append(self.allocator, value);
            }

            if (ev3 == .attribute) {
                if (std.mem.eql(u8, ev3.attribute.name, "mask")) {
                    list.mask = try ev3.attribute.dupeValue(self.allocator);
                } else if (std.mem.eql(u8, ev3.attribute.name, "enum")) {
                    list.@"enum" = try ev3.attribute.dupeValue(self.allocator);
                }
            }
            return list;
        }

        pub fn format(self: *const List, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            const width = (options.width orelse 0) + 2;

            try writer.writeAll(@typeName(List) ++ "{\n");

            try writer.writeByteNTimes(' ', width);
            try writer.writeAll(".type = \"");
            try writer.writeAll(self.type);
            try writer.writeAll("\",\n");

            try writer.writeByteNTimes(' ', width);
            try writer.writeAll(".name = \"");
            try writer.writeAll(self.name);
            try writer.writeAll("\",\n");

            if (self.values.items.len > 0) {
                try writer.writeByteNTimes(' ', width);
                try writer.writeAll(".values = .{\n");

                for (self.values.items) |*value| {
                    try writer.writeByteNTimes(' ', width + 2);
                    try value.format(fmt, .{
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
                try writer.writeAll(".values = .{},\n");
            }

            if (self.mask) |mask| {
                try writer.writeByteNTimes(' ', width);
                try writer.writeAll(".mask = \"");
                try writer.writeAll(mask);
                try writer.writeAll("\",\n");
            }

            if (self.@"enum") |e| {
                try writer.writeByteNTimes(' ', width);
                try writer.writeAll(".@\"enum\" = \"");
                try writer.writeAll(e);
                try writer.writeAll("\",\n");
            }

            try writer.writeByteNTimes(' ', width - 2);
            try writer.writeByte('}');
        }
    };

    pub fn deinit(self: Field, alloc: Allocator) void {
        switch (self) {
            .pad => {},
            inline else => |*v| @constCast(v).deinit(alloc),
        }
    }

    pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!?Field {
        const kind = blk: {
            while (true) {
                const document = parser.document;
                const mode = parser.mode;

                const v = parser.next() orelse break;

                switch (v) {
                    .comment => continue,
                    .close_tag => |t| {
                        if (std.meta.stringToEnum(std.meta.Tag(Field), t) == null) {
                            parser.document = document;
                            parser.mode = mode;
                            return null;
                        }
                        continue;
                    },
                    .open_tag => break :blk std.meta.stringToEnum(std.meta.Tag(Field), v.open_tag) orelse {
                        parser.document = document;
                        parser.mode = mode;
                        return null;
                    },
                    else => {
                        std.debug.print("{}\n", .{v});
                        return error.UnexpectedEvent;
                    },
                }
            }
            return error.UnexpectedEndOfFile;
        };

        return switch (kind) {
            .field => .{ .field = try Default.parse(self, parser) },
            .list => .{ .list = try List.parse(self, parser) },
            .pad => .{ .pad = try Pad.parse(self, parser) },
        };
    }

    pub fn format(self: *const Field, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        const width = (options.width orelse 0) + 2;

        try writer.writeAll(@typeName(Field) ++ "{\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeByte('.');
        try writer.writeAll(@tagName(std.meta.activeTag(self.*)));
        try writer.writeAll(" = ");

        switch (self.*) {
            inline else => |*v| try v.format(fmt, .{
                .width = width,
                .fill = options.fill,
                .precision = options.precision,
                .alignment = options.alignment,
            }, writer),
        }

        try writer.writeAll(",\n");
        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeByte('}');
    }
};
