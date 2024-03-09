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
        const ev1 = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev1 != .attribute) return error.UnexpectedEvent;
        if (!std.mem.eql(u8, ev1.attribute.name, "ref")) return error.UnknownAttribute;

        const ev2 = parser.next() orelse return error.UnexpectedEndOfFile;
        if (ev2 != .character_data) return error.UnexpectedEvent;

        return .{
            .ref = try ev1.attribute.dupeValue(self.allocator),
            .type = try self.allocator.dupe(u8, ev2.character_data),
        };
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
};

pub const Value = union(enum) {
    fieldref: []const u8,
    value: usize,
    op: Op,
    unop: Op,
    popcount: *Value,
    bitcase: *Value,
    field: Field.Default,
    pad: Field.Pad,
    list: Field.List,
    enumref: EnumRef,
    @"switch": NamedValue,
    fd: Field.Fd,

    pub fn deinit(self: *Value, alloc: Allocator) void {
        switch (self.*) {
            .fieldref => |fieldref| alloc.free(fieldref),
            .op, .unop => |*op| op.deinit(alloc),
            .bitcase, .popcount => |popcount| popcount.deinit(alloc),
            .@"switch" => |*nv| nv.deinit(alloc),
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
                    else => return error.UnexpectedEvent,
                }
            }
            return error.UnexpectedEndOfFile;
        };

        return switch (kind) {
            .field => .{ .field = try Field.Default.parse(self, parser) },
            .pad => .{ .pad = try Field.Pad.parse(self, parser) },
            .list => .{ .list = try Field.List.parse(self, parser) },
            .fd => .{ .fd = try Field.Fd.parse(self, parser) },
            .enumref => .{ .enumref = try EnumRef.parse(self, parser) },
            inline .op, .unop => |v| @unionInit(Value, @tagName(v), try Op.parse(self, parser)),
            inline .@"switch" => |v| @unionInit(Value, @tagName(v), try NamedValue.parse(self, parser)),
            inline .popcount, .bitcase => |v| blk: {
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
                    .op, .unop, .popcount, .field, .pad, .list, .@"switch", .bitcase, .enumref, .fd => unreachable,
                    inline .value => |v| @unionInit(Value, @tagName(v), try std.fmt.parseInt(usize, valueStr, 10)),
                    inline else => |k| @unionInit(Value, @tagName(k), valueStr),
                };
            },
        };
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
};

pub const Field = union(enum) {
    field: Default,
    pad: Pad,
    list: List,
    fd: Fd,
    @"switch": NamedValue,

    pub const Default = struct {
        type: []const u8,
        name: []const u8,
        mask: ?[]const u8,
        @"enum": ?[]const u8,

        pub fn deinit(self: Default, alloc: Allocator) void {
            alloc.free(self.type);
            alloc.free(self.name);

            if (self.mask) |m| alloc.free(m);
            if (self.@"enum") |e| alloc.free(e);
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
    };

    pub const List = struct {
        type: []const u8,
        name: []const u8,
        fieldref: ?[]const u8,
        mask: ?[]const u8,
        @"enum": ?[]const u8,

        pub fn deinit(self: *List, alloc: Allocator) void {
            alloc.free(self.type);
            alloc.free(self.name);

            if (self.fieldref) |fr| alloc.free(fr);
            if (self.mask) |m| alloc.free(m);
            if (self.@"enum") |e| alloc.free(e);
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
                .fieldref = null,
                .mask = null,
                .@"enum" = null,
            };
            errdefer list.deinit(self.allocator);

            {
                const doc = parser.document;
                const md = parser.mode;

                const ev4 = parser.next() orelse return error.UnexpectedEndOfFile;
                if (ev4 == .open_tag) {
                    if (std.mem.eql(u8, ev4.open_tag, "fieldref")) {
                        const ev5 = parser.next() orelse return error.UnexpectedEndOfFile;
                        if (ev5 != .character_data) return error.UnexpectedEvent;

                        list.fieldref = try self.allocator.dupe(u8, ev5.character_data);
                        _ = parser.next();
                    } else {
                        parser.document = doc;
                        parser.mode = md;
                    }
                } else {
                    parser.document = doc;
                    parser.mode = md;
                }
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
    };

    pub const Fd = struct {
        name: []const u8,

        pub fn deinit(self: Fd, alloc: Allocator) void {
            alloc.free(self.name);
        }

        pub fn parse(self: *Protocol, parser: *xml.Parser) Protocol.ParseError!Fd {
            const ev = parser.next() orelse return error.UnexpectedEndOfFile;
            if (ev != .attribute) return error.UnexpectedEvent;
            if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;

            const valueStr = try ev.attribute.dupeValue(self.allocator);
            errdefer self.allocator.free(valueStr);

            return .{ .name = valueStr };
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
                    else => return error.UnexpectedEvent,
                }
            }
            return error.UnexpectedEndOfFile;
        };

        return switch (kind) {
            .field => .{ .field = try Default.parse(self, parser) },
            .list => .{ .list = try List.parse(self, parser) },
            .pad => .{ .pad = try Pad.parse(self, parser) },
            .fd => .{ .fd = try Fd.parse(self, parser) },
            .@"switch" => .{ .@"switch" = try NamedValue.parse(self, parser) },
        };
    }
};
