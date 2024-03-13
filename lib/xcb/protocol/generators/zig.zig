const std = @import("std");
const options = @import("options");
const Protocol = @import("../../protocol.zig");
const Self = @This();

fn fmtExtFuncName(extName: ?[]const u8, name: []const u8, writer: anytype) !void {
    try writer.writeAll("xcb_");

    if (extName) |e| {
        for (e) |c| try writer.writeByte(std.ascii.toLower(c));
        try writer.writeByte('_');
    }

    for (name, 0..) |c, i| {
        if (std.ascii.isUpper(c)) {
            if (i > 0 and (((i + 1) < name.len and !std.ascii.isUpper(name[i + 1])) or std.ascii.isLower(name[i - 1]))) try writer.writeByte('_');

            try writer.writeByte(std.ascii.toLower(c));
        } else {
            try writer.writeByte(c);
        }
    }
}

fn fmtZigFunc(name: []const u8, writer: anytype) !void {
    var isCapital = false;
    for (name) |c| {
        if (c == '_') {
            isCapital = true;
            continue;
        }

        if (isCapital) {
            try writer.writeByte(std.ascii.toUpper(c));
            isCapital = false;
        } else {
            try writer.writeByte(c);
        }
    }
}

fn fmtFuncName(name: []const u8, writer: anytype) !void {
    const whenLower: ?usize = blk: {
        for (name, 0..) |c, i| {
            if (!std.ascii.isUpper(c)) break :blk i;
        }
        break :blk null;
    };

    if (whenLower) |i| {
        const x = if (i > 1) i - 1 else i;
        for (name[0..x]) |c| try writer.writeByte(std.ascii.toLower(c));
        try writer.writeAll(name[x..]);
    } else {
        try writer.writeAll(name);
    }
}

fn fmtTypeName(proto: *const Protocol, typeName: []const u8, writer: anytype) !void {
    if (proto.findImportForType(typeName)) |importKey| {
        const import = proto.imports.get(importKey) orelse unreachable;
        try writer.writeAll(import.headerName);
        try writer.writeByte('.');
        try writer.writeAll(typeName);
    } else if (std.mem.indexOf(u8, typeName, ":")) |i| {
        try writer.writeAll(typeName[0..i]);
        try writer.writeByte('.');
        try writer.writeAll(typeName[(i + 1)..]);
    } else if (std.mem.eql(u8, typeName, "CARD8") or std.mem.eql(u8, typeName, "BYTE") or std.mem.eql(u8, typeName, "BOOL") or std.mem.eql(u8, typeName, "void")) {
        try writer.writeAll("u8");
    } else if (std.mem.eql(u8, typeName, "CARD16")) {
        try writer.writeAll("u16");
    } else if (std.mem.eql(u8, typeName, "CARD32")) {
        try writer.writeAll("u32");
    } else if (std.mem.eql(u8, typeName, "CARD64")) {
        try writer.writeAll("u64");
    } else if (std.mem.eql(u8, typeName, "INT8")) {
        try writer.writeAll("i8");
    } else if (std.mem.eql(u8, typeName, "INT16")) {
        try writer.writeAll("i16");
    } else if (std.mem.eql(u8, typeName, "INT32")) {
        try writer.writeAll("i32");
    } else if (std.mem.eql(u8, typeName, "INT64")) {
        try writer.writeAll("i64");
    } else if (std.mem.eql(u8, typeName, "char")) {
        try writer.writeAll("u8");
    } else if (std.mem.eql(u8, typeName, "float")) {
        try writer.writeAll("f32");
    } else if (std.mem.eql(u8, typeName, "double")) {
        try writer.writeAll("f64");
    } else {
        try writer.writeAll(typeName);
    }
}

pub fn fmtField(proto: *const Protocol, padNumber: usize, field: *const Protocol.Field, _: usize, writer: anytype) !void {
    switch (field.*) {
        .pad => |p| {
            try writer.writeAll("pad");
            try std.fmt.formatInt(padNumber, 10, .lower, .{}, writer);
            try writer.writeAll(": [");
            try std.fmt.formatInt(p.bytes, 10, .lower, .{}, writer);
            try writer.writeAll("]u8,\n");
        },
        inline else => |v| {
            if (field.* == .list) {
                try writer.writeAll(v.name);
                try writer.writeAll("_length");
            } else {
                try std.zig.fmtId(v.name).format("", .{}, writer);
            }

            try writer.writeAll(": ");
            if (@hasField(@TypeOf(v), "type")) {
                try fmtTypeName(proto, v.type, writer);
            } else if (field.* == .fd) {
                try writer.writeAll("std.os.fd_t");
            } else if (field.* == .@"switch") {
                try writer.writeAll("[*] const u32");
            }
            try writer.writeAll(",\n");
        },
    }
}

pub fn fmtFields(proto: *const Protocol, fields: []const Protocol.Field, parentName: []const u8, parentNameFunc: []const u8, initPads: usize, offset: usize, width: usize, writer: anytype) !void {
    var pads: usize = initPads;
    if (fields.len > offset) {
        for (fields[offset..]) |*field| {
            if (field.* == .list) {
                if (field.list.fieldref != null) continue;
            }

            if (field.* == .pad and field.pad == .@"align") continue;

            try writer.writeByteNTimes(' ', width);
            try fmtField(proto, pads, field, width, writer);
            if (field.* == .pad) pads += 1;
        }
    }

    try writer.writeAll("\n");
    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const Iterator = extern struct {\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("data: *");
    try writer.writeAll(parentName);
    try writer.writeAll(",\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("rem: c_int,\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("index: c_int,\n\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("extern fn ");
    try fmtExtFuncName(proto.extName, parentNameFunc, writer);
    try writer.writeAll("_next(*Iterator) void;\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("pub fn next(self: *Iterator) ?*");
    try writer.writeAll(parentName);
    try writer.writeAll(" {\n");

    try writer.writeByteNTimes(' ', width + 4);
    try writer.writeAll("if (self.rem == 0) return null;\n");

    try writer.writeByteNTimes(' ', width + 4);
    try writer.writeAll("const iteratorValue = self.data;\n");

    try writer.writeByteNTimes(' ', width + 4);
    try fmtExtFuncName(proto.extName, parentNameFunc, writer);
    try writer.writeAll("_next(self);\n");

    try writer.writeByteNTimes(' ', width + 4);
    try writer.writeAll("return iteratorValue;\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("}\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n");

    for (fields) |field| {
        if (field != .list) continue;

        try writer.writeAll("\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("extern fn ");
        try fmtExtFuncName(proto.extName, parentNameFunc, writer);
        try writer.writeAll("_");
        try writer.writeAll(field.list.name);
        try writer.writeAll("_length(*const ");
        try writer.writeAll(parentName);
        try writer.writeAll(") c_int;\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("pub const ");
        try fmtZigFunc(field.list.name, writer);
        try writer.writeAll("Length = ");
        try fmtExtFuncName(proto.extName, parentNameFunc, writer);
        try writer.writeAll("_");
        try writer.writeAll(field.list.name);
        try writer.writeAll("_length;\n");

        if (proto.isPrimitiveType(field.list.type)) {
            try writer.writeAll("\n");
            try writer.writeByteNTimes(' ', width);
            try writer.writeAll("extern fn ");
            try fmtExtFuncName(proto.extName, parentNameFunc, writer);
            try writer.writeAll("_");
            try writer.writeAll(field.list.name);
            try writer.writeAll("(*const ");
            try writer.writeAll(parentName);
            try writer.writeAll(") [*]const ");
            try fmtTypeName(proto, field.list.type, writer);
            try writer.writeAll(";\n");

            try writer.writeByteNTimes(' ', width);
            try writer.writeAll("pub fn ");
            try fmtZigFunc(field.list.name, writer);
            try writer.writeAll("(self: *const ");
            try writer.writeAll(parentName);
            try writer.writeAll(") []const ");
            try fmtTypeName(proto, field.list.type, writer);
            try writer.writeAll("{\n");

            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeAll("const len: usize = @intCast(");
            try fmtExtFuncName(proto.extName, parentNameFunc, writer);
            try writer.writeAll("_");
            try writer.writeAll(field.list.name);
            try writer.writeAll("_length(self));\n");

            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeAll("const slice = ");
            try fmtExtFuncName(proto.extName, parentNameFunc, writer);
            try writer.writeAll("_");
            try writer.writeAll(field.list.name);
            try writer.writeAll("(self);\n");

            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeAll("return slice[0..len];\n");

            try writer.writeByteNTimes(' ', width);
            try writer.writeAll("}\n");
        } else {
            try writer.writeAll("\n");
            try writer.writeByteNTimes(' ', width);
            try writer.writeAll("extern fn ");
            try fmtExtFuncName(proto.extName, parentNameFunc, writer);
            try writer.writeAll("_");
            try writer.writeAll(field.list.name);
            try writer.writeAll("_iterator(*const ");
            try writer.writeAll(parentName);
            try writer.writeAll(") ");
            try fmtTypeName(proto, field.list.type, writer);
            try writer.writeAll(".Iterator;\n\n");

            try writer.writeByteNTimes(' ', width);
            try writer.writeAll("pub const ");
            try fmtZigFunc(field.list.name, writer);
            try writer.writeAll("Iterator = ");
            try fmtExtFuncName(proto.extName, parentNameFunc, writer);
            try writer.writeAll("_");
            try writer.writeAll(field.list.name);
            try writer.writeAll("_iterator;\n");
        }
    }
}

pub fn fmtStruct(proto: *const Protocol, str: *const Protocol.Struct, width: usize, writer: anytype) !void {
    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const ");
    try writer.writeAll(str.name);
    try writer.writeAll(" = extern struct {\n");

    try fmtFields(proto, str.fields.items, str.name, str.name, 0, 0, width + 2, writer);

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n");
}

pub fn fmtUnion(proto: *const Protocol, u: *const Protocol.Union, width: usize, writer: anytype) !void {
    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const ");
    try writer.writeAll(u.name);
    try writer.writeAll(" = extern union {\n");

    try fmtFields(proto, u.fields.items, u.name, u.name, 0, 0, width + 2, writer);

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n");
}

pub fn fmtRequest(proto: *const Protocol, req: *const Protocol.Request, width: usize, writer: anytype) !void {
    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const ");
    try writer.writeAll(req.name);
    try writer.writeAll("Request = extern struct {\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("pub const Opcode = ");
    try std.fmt.formatInt(req.opcode, 10, .lower, .{}, writer);
    try writer.writeAll(";\n\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("major_opcode: u8,\n");

    try writer.writeByteNTimes(' ', width + 2);
    if (proto.extName) |_| {
        try writer.writeAll("minor_opcode: u8,\n");
    } else {
        try writer.writeAll("pad0: u8,\n");
    }

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("length: u16,\n");

    {
        var name = std.ArrayList(u8).init(proto.allocator);
        defer name.deinit();
        try name.appendSlice(req.name);
        try name.appendSlice("Request");

        try fmtFields(proto, req.fields.items, name.items, req.name, 1, 0, width + 2, writer);
    }

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n\n");

    if (req.reply.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("pub const ");
        try writer.writeAll(req.name);
        try writer.writeAll("Reply = extern struct {\n");

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("response_type: u8,\n");

        {
            var name = std.ArrayList(u8).init(proto.allocator);
            defer name.deinit();
            try name.appendSlice(req.name);
            try name.appendSlice("Reply");

            try writer.writeByteNTimes(' ', width + 2);
            try fmtField(proto, 0, &req.reply.items[0], width + 2, writer);

            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeAll("sequence: u16,\n");

            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeAll("length: u32,\n");

            try fmtFields(proto, req.reply.items, name.items, req.name, if (req.reply.items[0] == .pad) 1 else 0, 1, width + 2, writer);

            const fdCount = blk: {
                var fds: usize = 0;
                for (req.reply.items) |f| {
                    if (f == .fd) fds += 1;
                }
                break :blk fds;
            };

            if (fdCount > 0) {
                try writer.writeAll("\n");
                try writer.writeByteNTimes(' ', width + 2);
                try writer.writeAll("extern fn ");
                try fmtExtFuncName(proto.extName, name.items, writer);
                try writer.writeAll("_fds(*const xcb.Connection, *const ");
                try writer.writeAll(name.items);
                try writer.writeAll(") ?[*]const c_int;\n\n");

                try writer.writeByteNTimes(' ', width + 2);
                try writer.writeAll("pub fn fds(self: *const ");
                try writer.writeAll(name.items);
                try writer.writeAll(", conn: *const xcb.Connection) ?[]const c_int {\n");

                try writer.writeByteNTimes(' ', width + 4);
                try writer.writeAll("const fdsValue = ");
                try fmtExtFuncName(proto.extName, name.items, writer);
                try writer.writeAll("_fds(conn, self) orelse return null;\n");

                try writer.writeByteNTimes(' ', width + 4);
                try writer.writeAll("return fdsValue[0..");
                try std.fmt.formatInt(fdCount, 10, .lower, .{}, writer);
                try writer.writeAll("];\n");

                try writer.writeByteNTimes(' ', width + 2);
                try writer.writeAll("}\n");
            }
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("};\n\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("pub const ");
        try writer.writeAll(req.name);
        try writer.writeAll("Cookie = extern struct {\n");

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("seq: c_uint,\n\n");

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("extern fn ");
        try fmtExtFuncName(proto.extName, req.name, writer);
        try writer.writeAll("_reply(*xcb.Connection, ");
        try writer.writeAll(req.name);
        try writer.writeAll("Cookie, ?*?*xcb.GenericError) ?*");
        try writer.writeAll(req.name);
        try writer.writeAll("Reply;\n");

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("pub fn reply(self: ");
        try writer.writeAll(req.name);
        try writer.writeAll("Cookie, conn: *xcb.Connection) !*");
        try writer.writeAll(req.name);
        try writer.writeAll("Reply {\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("var err: ?*xcb.GenericError = null;\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("const resp = ");
        try fmtExtFuncName(proto.extName, req.name, writer);
        try writer.writeAll("_reply(conn, self, &err);\n\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("if (resp == null and err != null) {\n");

        // TODO: convert XCB errors into Zig ones
        try writer.writeByteNTimes(' ', width + 6);
        try writer.writeAll("return error.GenericError;\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("}\n\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("assert(resp != null and err == null);\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("return resp.?;\n");

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("}\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("};\n\n");
    }

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("extern fn ");
    try fmtExtFuncName(proto.extName, req.name, writer);
    try writer.writeAll("(*xcb.Connection");

    for (req.fields.items) |field| {
        switch (field) {
            .pad => {},
            inline else => |v| {
                try writer.writeAll(", ");

                if (field == .list) {
                    if (field.list.fieldref == null) {
                        try writer.writeAll("u32, ");
                    }

                    try writer.writeAll("[*]const ");
                }

                if (@hasField(@TypeOf(v), "type")) {
                    try fmtTypeName(proto, v.type, writer);
                } else if (field == .fd) {
                    try writer.writeAll("std.os.fd_t");
                } else if (field == .@"switch") {
                    try writer.writeAll("[*] const u32");
                }
            },
        }
    }

    try writer.writeAll(") ");

    if (req.reply.items.len > 0) {
        try writer.writeAll(req.name);
        try writer.writeAll("Cookie");
    } else {
        try writer.writeAll("xcb.VoidCookie");
    }

    try writer.writeAll(";\n");

    var name = std.ArrayList(u8).init(proto.allocator);
    defer name.deinit();
    try fmtFuncName(req.name, name.writer());

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const ");
    try std.zig.fmtId(name.items).format("", .{}, writer);
    try writer.writeAll(" = ");
    try fmtExtFuncName(proto.extName, req.name, writer);
    try writer.writeAll(";\n");
}

pub fn fmtXidUnion(proto: *const Protocol, xidunion: *const Protocol.XidUnion, width: usize, writer: anytype) !void {
    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const ");
    try writer.writeAll(xidunion.name);
    try writer.writeAll(" = extern union {\n");

    for (xidunion.types.items) |t| {
        try writer.writeByteNTimes(' ', width + 2);

        const name = try std.ascii.allocLowerString(proto.allocator, t);
        defer proto.allocator.free(name);

        try std.zig.fmtId(name).format("", .{}, writer);

        try writer.writeAll(": ");
        try fmtTypeName(proto, t, writer);
        try writer.writeAll(",\n");
    }

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n");
}

pub fn fmtEnum(proto: *const Protocol, e: *const Protocol.Enum, width: usize, writer: anytype) !void {
    _ = proto;

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const ");
    try writer.writeAll(e.name);
    try writer.writeAll(" = ");
    if (e.isBits()) {
        try writer.writeAll("struct");
    } else {
        try writer.writeAll("enum(");

        {
            const from = e.min();
            const to = e.max();
            if (from == 0 and to == 0) {
                try writer.writeAll("u0");
            } else {
                const signedness: std.builtin.Signedness = if (from < 0) .signed else .unsigned;
                const largest_positive_integer = @max(if (from < 0) (-from) - 1 else from, to); // two's complement
                const base = std.math.log2(largest_positive_integer);
                const upper = (@as(usize, 1) << @intCast(base)) - 1;
                var magnitude_bits = if (upper >= largest_positive_integer) base else base + 1;
                if (signedness == .signed) {
                    magnitude_bits += 1;
                }
                try writer.writeByte(@tagName(signedness)[0]);
                try std.fmt.formatInt(magnitude_bits, 10, .lower, .{}, writer);
            }
        }

        try writer.writeByte(')');
    }
    try writer.writeAll(" {\n");

    var iter = e.items.iterator();
    while (iter.next()) |entry| {
        try writer.writeByteNTimes(' ', width + 2);
        if (entry.value_ptr.bit) try writer.writeAll("pub const ");

        try std.zig.fmtId(entry.key_ptr.*).format("", .{}, writer);
        try writer.writeAll(" = ");
        try std.fmt.formatInt(entry.value_ptr.index, 10, .lower, .{}, writer);

        if (entry.value_ptr.bit) try writer.writeAll(";\n") else try writer.writeAll(",\n");
    }

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n");
}

pub fn fmtEventStruct(proto: *const Protocol, es: *const Protocol.EventStruct, width: usize, writer: anytype) !void {
    _ = proto;

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const ");
    try writer.writeAll(es.name);
    try writer.writeAll(" = extern union {\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n");
}

pub fn fmtEvent(proto: *const Protocol, ev: *const Protocol.Event, width: usize, writer: anytype) !void {
    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const ");
    try writer.writeAll(ev.name);
    try writer.writeAll(" = extern struct {\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("pub const Number = ");
    try std.fmt.formatInt(ev.number, 10, .lower, .{}, writer);
    try writer.writeAll(";\n");

    try writer.writeByteNTimes(' ', width + 2);
    try writer.writeAll("response_type: u8,\n");

    {
        var name = std.ArrayList(u8).init(proto.allocator);
        defer name.deinit();
        try name.appendSlice("events.");
        try name.appendSlice(ev.name);

        try writer.writeByteNTimes(' ', width + 2);
        if (ev.fields.items.len > 0) {
            try fmtField(proto, 0, &ev.fields.items[0], width + 2, writer);
        } else {
            try writer.writeAll("pad0: u8,\n");
        }

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("sequence: u16,\n");

        if (ev.fields.items.len > 1) {
            try fmtFields(proto, ev.fields.items, name.items, ev.name, if (ev.fields.items[0] == .pad) 1 else 0, 1, width + 2, writer);
        }
    }

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n");
}

pub fn fmtProtocol(proto: *const Protocol, width: usize, writer: anytype) !void {
    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("const std = @import(\"std\");\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("const assert = std.debug.assert;\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("const xcb = @import(\"" ++ options.importName ++ "\");\n\n");

    if (proto.extName) |extName| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("pub const extName = \"");
        try std.zig.fmtEscapes(extName).format("", .{}, writer);
        try writer.writeAll("\";\n");
    }

    if (proto.version.major > 0 or proto.version.minor > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("pub const version = std.SemanticVersion{ .major = ");
        try std.fmt.formatInt(proto.version.major, 10, .lower, .{}, writer);
        try writer.writeAll(", .minor = ");
        try std.fmt.formatInt(proto.version.minor, 10, .lower, .{}, writer);
        try writer.writeAll(", .patch = 0 };\n");
    }

    {
        var iter = proto.typedefs.iterator();
        while (iter.next()) |entry| {
            try writer.writeByteNTimes(' ', width);
            try writer.writeAll("pub const ");
            try std.zig.fmtId(entry.key_ptr.*).format("", .{}, writer);
            try writer.writeAll(" = ");
            try fmtTypeName(proto, entry.value_ptr.*, writer);
            try writer.writeAll(";\n");
        }
    }

    for (proto.xidtypes.items) |xidtype| {
        try writer.writeAll("\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("pub const ");
        try std.zig.fmtId(xidtype).format("", .{}, writer);
        try writer.writeAll(" = extern struct {\n");

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("value: u32,\n\n");

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("pub const Iterator = extern struct {\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("data: *u32");
        try writer.writeAll(",\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("rem: c_int,\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("index: c_int,\n\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("extern fn ");
        try fmtExtFuncName(proto.extName, xidtype, writer);
        try writer.writeAll("_next(*Iterator) void;\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("pub fn next(self: *Iterator) ?*u32 {\n");

        try writer.writeByteNTimes(' ', width + 6);
        try writer.writeAll("if (self.rem == 0) return null;\n");

        try writer.writeByteNTimes(' ', width + 6);
        try writer.writeAll("const value = self.data;\n");

        try writer.writeByteNTimes(' ', width + 6);
        try fmtExtFuncName(proto.extName, xidtype, writer);
        try writer.writeAll("_next(self);\n");

        try writer.writeByteNTimes(' ', width + 6);
        try writer.writeAll("return value;\n");

        try writer.writeByteNTimes(' ', width + 4);
        try writer.writeAll("}\n");

        try writer.writeByteNTimes(' ', width + 2);
        try writer.writeAll("};\n");

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("};\n");
    }

    for (proto.xidunions.items) |*xidunion| {
        try writer.writeAll("\n");
        try fmtXidUnion(proto, xidunion, width, writer);
    }

    for (proto.enums.items) |*e| {
        try writer.writeAll("\n");
        try fmtEnum(proto, e, width, writer);
    }

    for (proto.eventstructs.items) |*es| {
        try writer.writeAll("\n");
        try fmtEventStruct(proto, es, width, writer);
    }

    for (proto.structs.items) |*str| {
        try writer.writeAll("\n");
        try fmtStruct(proto, str, width, writer);
    }

    for (proto.unions.items) |*u| {
        try writer.writeAll("\n");
        try fmtUnion(proto, u, width, writer);
    }

    for (proto.requests.items) |*req| {
        try writer.writeAll("\n");
        try fmtRequest(proto, req, width, writer);
    }

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("pub const events = struct {\n");

    for (proto.events.items) |*ev| {
        try writer.writeAll("\n");
        try fmtEvent(proto, ev, width + 2, writer);
    }

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll("};\n");
}

pub fn fmtProtocols(protos: []const *Protocol, width: usize, writer: anytype) !void {
    for (protos, 0..) |proto, i| {
        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeAll("pub const ");
        try std.zig.fmtId(proto.headerName).format("", .{}, writer);
        try writer.writeAll(" = struct {\n");

        try fmtProtocol(proto, width, writer);

        try writer.writeByteNTimes(' ', width - 2);
        try writer.writeAll("};");

        if (i < (protos.len - 1)) try writer.writeByteNTimes('\n', 2);
    }
}

test "Generate correct function names" {
    {
        var list = std.ArrayList(u8).init(std.testing.allocator);
        defer list.deinit();
        try fmtExtFuncName(null, "CreateWindow", list.writer());
        try std.testing.expectEqualStrings("xcb_create_window", list.items);
    }

    {
        var list = std.ArrayList(u8).init(std.testing.allocator);
        defer list.deinit();
        try fmtExtFuncName(null, "CreateGC", list.writer());
        try std.testing.expectEqualStrings("xcb_create_gc", list.items);
    }
}
