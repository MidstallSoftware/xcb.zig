const std = @import("std");
const Protocol = @import("../../protocol.zig");
const Self = @This();

pub fn fmtCopy(copy: *const Protocol.Copy, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Copy) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".kind = .");
    try std.zig.fmtId(@tagName(copy.kind)).format("", .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(copy.name);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".number = ");
    try std.fmt.formatInt(copy.number, 10, .lower, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".ref = \"");
    try writer.writeAll(copy.ref);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtEnumItem(item: *const Protocol.Enum.Item, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Enum.Item) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".index = ");
    try std.fmt.formatInt(item.index, 10, .lower, .{}, writer);
    try writer.writeAll(",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".bit = ");
    try writer.writeAll(if (item.bit) "true" else "false");
    try writer.writeAll(",\n");

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtEnum(e: *const Protocol.Enum, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Enum) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(e.name);
    try writer.writeAll("\",\n");

    if (e.items.count() > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".items = .{\n");

        var iter = e.items.iterator();
        while (iter.next()) |item| {
            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeByte('.');
            try writer.writeAll(item.key_ptr.*);
            try writer.writeAll(" = ");
            try fmtEnumItem(item.value_ptr, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".items = .{},\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtFieldDefault(field: *const Protocol.Field.Default, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Field.Default) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".type = \"");
    try writer.writeAll(field.type);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(field.name);
    try writer.writeAll("\",\n");

    if (field.mask) |mask| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".mask = \"");
        try writer.writeAll(mask);
        try writer.writeAll("\",\n");
    }

    if (field.@"enum") |e| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".@\"enum\" = \"");
        try writer.writeAll(e);
        try writer.writeAll("\",\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtFieldPad(field: *const Protocol.Field.Pad, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Field.Pad) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeByte('.');
    try writer.writeAll(@tagName(std.meta.activeTag(field.*)));
    try writer.writeAll(" = ");

    switch (field.*) {
        inline else => |v| try std.fmt.formatInt(v, 10, .lower, .{}, writer),
    }

    try writer.writeAll(",\n");
    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtFieldList(field: *const Protocol.Field.List, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Field.List) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".type = \"");
    try writer.writeAll(field.type);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(field.name);
    try writer.writeAll("\",\n");

    if (field.fieldref) |fieldref| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fieldref = \"");
        try writer.writeAll(fieldref);
        try writer.writeAll("\",\n");
    }

    if (field.mask) |mask| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".mask = \"");
        try writer.writeAll(mask);
        try writer.writeAll("\",\n");
    }

    if (field.@"enum") |e| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".@\"enum\" = \"");
        try writer.writeAll(e);
        try writer.writeAll("\",\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtFieldFd(field: *const Protocol.Field.Fd, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Field.Fd) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(field.name);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtField(field: *const Protocol.Field, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Field) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeByte('.');
    try writer.writeAll(@tagName(std.meta.activeTag(field.*)));
    try writer.writeAll(" = ");

    switch (field.*) {
        .field => |*v| try fmtFieldDefault(v, width, writer),
        .pad => |*v| try fmtFieldPad(v, width, writer),
        .list => |*v| try fmtFieldList(v, width, writer),
        .fd => |*v| try fmtFieldFd(v, width, writer),
        .@"switch" => {},
    }

    try writer.writeAll(",\n");
    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtError(e: *const Protocol.Error, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Error) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(e.name);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".number = ");
    try std.fmt.formatInt(e.number, 10, .lower, .{}, writer);
    try writer.writeAll(",\n");

    if (e.fields.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{\n");

        for (e.fields.items) |*f| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtField(f, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{},\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtOp(op: *const Protocol.Op, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Op) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".kind = ");
    try std.zig.fmtId(@tagName(op.kind)).format("", .{}, writer);
    try writer.writeAll(",\n");

    if (op.values.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".values = .{\n");

        for (op.values.items) |*value| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtValue(value, width + 2, writer);
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

pub fn fmtEnumRef(value: *const Protocol.EnumRef, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.EnumRef) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".ref = \"");
    try writer.writeAll(value.ref);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".type = \"");
    try writer.writeAll(value.type);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtNamedValue(value: *const Protocol.NamedValue, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.NamedValue) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(value.name);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try fmtValue(value.value, width, writer);
    try writer.writeAll(",\n");

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtValue(value: *const Protocol.Value, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Value) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeByte('.');
    try writer.writeAll(@tagName(std.meta.activeTag(value.*)));
    try writer.writeAll(" = ");

    switch (value.*) {
        .value => |v| try std.fmt.formatInt(v, 10, .lower, .{}, writer),
        .fieldref => |v| {
            try writer.writeByte('"');
            try writer.writeAll(v);
            try writer.writeByte('"');
        },
        .popcount => |v| try fmtValue(v, width, writer),
        .field => |*v| try fmtFieldDefault(v, width, writer),
        .pad => |*v| try fmtFieldPad(v, width, writer),
        .list => |*v| try fmtFieldList(v, width, writer),
        .op, .unop => |*v| try fmtOp(v, width, writer),
        .enumref => |*v| try fmtEnumRef(v, width, writer),
        .bitcase, .@"switch" => |*v| try fmtNamedValue(v, width, writer),
    }

    try writer.writeAll(",\n");
    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtEvent(ev: *const Protocol.Event, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Event) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(ev.name);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".number = ");
    try std.fmt.formatInt(ev.number, 10, .lower, .{}, writer);
    try writer.writeAll(",\n");

    if (ev.fields.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{\n");

        for (ev.fields.items) |*f| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtField(f, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{},\n");
    }

    if (ev.noSequenceNumber) |noSequenceNumber| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".noSequenceNumber = ");
        try writer.writeAll(if (noSequenceNumber) "true" else "false");
        try writer.writeAll(",\n");
    }

    if (ev.xge) |xge| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".xge = ");
        try writer.writeAll(if (xge) "true" else "false");
        try writer.writeAll(",\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtXidUnion(xidunion: *const Protocol.XidUnion, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.XidUnion) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(xidunion.name);
    try writer.writeAll("\",\n");

    if (xidunion.types.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".types = .{\n");

        for (xidunion.types.items) |t| {
            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeByte('"');
            try writer.writeAll(t);
            try writer.writeAll("\",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".types = .{},\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtStruct(s: *const Protocol.Struct, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Struct) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(s.name);
    try writer.writeAll("\",\n");

    if (s.fields.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{\n");

        for (s.fields.items) |*f| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtField(f, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{},\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtUnion(u: *const Protocol.Union, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Union) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(u.name);
    try writer.writeAll("\",\n");

    if (u.fields.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{\n");

        for (u.fields.items) |*f| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtField(f, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{},\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtRequest(req: *const Protocol.Request, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol.Request) ++ "{\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".name = \"");
    try writer.writeAll(req.name);
    try writer.writeAll("\",\n");

    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".opcode = ");
    try std.fmt.formatInt(req.opcode, 10, .lower, .{}, writer);
    try writer.writeAll(",\n");

    if (req.fields.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{\n");

        for (req.fields.items) |*f| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtField(f, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".fields = .{},\n");
    }

    if (req.reply.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".reply = .{\n");

        for (req.reply.items) |*f| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtField(f, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    }

    if (req.combineAdjacent) |combineAdjacent| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".combineAdjacent = ");
        try writer.writeAll(if (combineAdjacent) "true" else "false");
        try writer.writeAll(",\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtProtocol(proto: *const Protocol, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(@typeName(Protocol) ++ "{\n");
    try writer.writeByteNTimes(' ', width);
    try writer.writeAll(".headerName = \"");
    try writer.writeAll(proto.headerName);
    try writer.writeAll("\",\n");

    if (proto.extName) |extName| {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".extName = \"");
        try writer.writeAll(extName);
        try writer.writeAll("\",\n");
    }

    if (proto.version.major > 0 or proto.version.minor > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".version = \"");
        try std.fmt.format(writer, "{d}.{d}", .{ proto.version.major, proto.version.minor });
        try writer.writeAll("\",\n");
    }

    if (proto.imports.count() > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".imports = .{\n");

        var iter = proto.imports.valueIterator();
        while (iter.next()) |import| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtProtocol(import.*, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".imports = .{},\n");
    }

    if (proto.enums.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".enums = .{\n");

        for (proto.enums.items) |*e| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtEnum(e, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".enums = .{},\n");
    }

    if (proto.xidtypes.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".xidtypes = .{\n");

        for (proto.xidtypes.items) |item| {
            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeByte('"');
            try writer.writeAll(item);
            try writer.writeAll("\",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".xidtypes = .{},\n");
    }

    if (proto.xidunions.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".xidunions = .{\n");

        for (proto.xidunions.items) |*item| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtXidUnion(item, width + 2, writer);
            try writer.writeAll("\",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".xidunions = .{},\n");
    }

    if (proto.typedefs.count() > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".typedefs = .{\n");

        var iter = proto.typedefs.iterator();
        while (iter.next()) |entry| {
            try writer.writeByteNTimes(' ', width + 2);
            try writer.writeByte('.');
            try writer.writeAll(entry.key_ptr.*);
            try writer.writeAll(" = \"");
            try writer.writeAll(entry.value_ptr.*);
            try writer.writeAll("\",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".typedefs = .{},\n");
    }

    if (proto.errors.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".errors = .{\n");

        for (proto.errors.items) |*err| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtError(err, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".errors = .{},\n");
    }

    if (proto.structs.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".structs = .{\n");

        for (proto.structs.items) |*str| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtStruct(str, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".structs = .{},\n");
    }

    if (proto.requests.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".requests = .{\n");

        for (proto.requests.items) |*req| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtRequest(req, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".requests = .{},\n");
    }

    if (proto.events.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".events = .{\n");

        for (proto.events.items) |*ev| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtEvent(ev, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".events = .{},\n");
    }

    if (proto.copies.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".copies = .{\n");

        for (proto.copies.items) |*copy| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtCopy(copy, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".copies = .{},\n");
    }

    if (proto.unions.items.len > 0) {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".unions = .{\n");

        for (proto.unions.items) |*u| {
            try writer.writeByteNTimes(' ', width + 2);
            try fmtUnion(u, width + 2, writer);
            try writer.writeAll(",\n");
        }

        try writer.writeByteNTimes(' ', width);
        try writer.writeAll("},\n");
    } else {
        try writer.writeByteNTimes(' ', width);
        try writer.writeAll(".unions = .{},\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeByte('}');
}

pub fn fmtProtocols(protos: []const *Protocol, width: usize, writer: anytype) @TypeOf(writer).Error!void {
    try writer.writeAll(".{\n");

    for (protos) |proto| {
        try writer.writeByteNTimes(' ', width);
        try fmtProtocol(proto, width + 2, writer);
        try writer.writeAll(",\n");
    }

    try writer.writeByteNTimes(' ', width - 2);
    try writer.writeAll("}");
}
