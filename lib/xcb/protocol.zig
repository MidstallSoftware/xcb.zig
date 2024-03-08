const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("../xml.zig");
const Protocol = @This();

pub const generators = @import("protocol/generators.zig");

pub const Options = struct {
    directory: std.fs.Dir,
    source: std.fs.File,
};

pub const Copy = @import("protocol/copy.zig");
pub const Enum = @import("protocol/enum.zig");
pub const Error = @import("protocol/error.zig");
pub const Event = @import("protocol/event.zig");
pub const EventStruct = @import("protocol/eventstruct.zig");
pub usingnamespace @import("protocol/field.zig");
pub const Request = @import("protocol/request.zig");
pub const Struct = @import("protocol/struct.zig");
pub const Union = @import("protocol/union.zig");
pub const XidUnion = @import("protocol/xidunion.zig");

pub const ParseError = Allocator.Error || std.fs.Dir.OpenError || std.fs.File.OpenError || std.fs.File.ReadError || std.fmt.ParseIntError || error{
    UnexpectedEndOfFile,
    UnexpectedEvent,
    UnknownAttribute,
    DuplicateAttributes,
    MissingNameOrVersion,
};

allocator: Allocator,
imports: std.StringHashMapUnmanaged(*Protocol) = .{},
enums: std.ArrayListUnmanaged(Enum) = .{},
xidtypes: std.ArrayListUnmanaged([]const u8) = .{},
xidunions: std.ArrayListUnmanaged(XidUnion) = .{},
typedefs: std.StringHashMapUnmanaged([]const u8) = .{},
errors: std.ArrayListUnmanaged(Error) = .{},
structs: std.ArrayListUnmanaged(Struct) = .{},
requests: std.ArrayListUnmanaged(Request) = .{},
events: std.ArrayListUnmanaged(Event) = .{},
copies: std.ArrayListUnmanaged(Copy) = .{},
unions: std.ArrayListUnmanaged(Union) = .{},
eventstructs: std.ArrayListUnmanaged(EventStruct) = .{},
version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 0 },
headerName: []const u8,
extName: ?[]const u8 = null,

pub fn create(alloc: Allocator, options: Options) !*Protocol {
    const src = try options.source.readToEndAlloc(alloc, (try options.source.metadata()).size());
    defer alloc.free(src);

    var parser = xml.Parser.init(src);

    const self = try alloc.create(Protocol);
    errdefer self.deinit();

    self.* = .{
        .allocator = alloc,
        .headerName = undefined,
    };

    while (parser.next()) |ev| switch (ev) {
        .open_tag => |tag| if (std.mem.eql(u8, tag, "xcb")) {
            try self.parseToplevel(&parser, options.directory);
            return self;
        },
        else => {},
    };

    return error.UnexpectedEndOfFile;
}

pub fn hasType(self: *const Protocol, typeName: []const u8) bool {
    for (self.enums.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }

    for (self.xidtypes.items) |e| {
        if (std.mem.eql(u8, e, typeName)) return true;
    }

    for (self.xidunions.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }

    {
        var iter = self.typedefs.keyIterator();
        while (iter.next()) |e| {
            if (std.mem.eql(u8, e.*, typeName)) return true;
        }
    }

    for (self.errors.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }

    for (self.structs.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }

    for (self.requests.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }

    for (self.events.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }

    for (self.copies.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }

    for (self.unions.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }

    for (self.eventstructs.items) |e| {
        if (std.mem.eql(u8, e.name, typeName)) return true;
    }
    return false;
}

pub fn findImportForType(self: *const Protocol, typeName: []const u8) ?[]const u8 {
    var iter = self.imports.iterator();
    while (iter.next()) |entry| {
        if (hasType(entry.value_ptr.*, typeName)) return entry.key_ptr.*;
    }
    return null;
}

fn parseToplevel(self: *Protocol, parser: *xml.Parser, directory: std.fs.Dir) ParseError!void {
    while (parser.next()) |ev| switch (ev) {
        .attribute => |attr| if (std.mem.eql(u8, attr.name, "header")) {
            self.headerName = try attr.dupeValue(self.allocator);
        } else if (std.mem.eql(u8, attr.name, "extension-name")) {
            self.extName = try attr.dupeValue(self.allocator);
        } else if (std.mem.eql(u8, attr.name, "major-version")) {
            const value = try attr.dupeValue(self.allocator);
            defer self.allocator.free(value);
            self.version.major = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, attr.name, "minor-version")) {
            const value = try attr.dupeValue(self.allocator);
            defer self.allocator.free(value);
            self.version.minor = try std.fmt.parseInt(usize, value, 10);
        },
        .open_tag => |tag| if (std.mem.eql(u8, tag, "import")) {
            try self.parseImport(parser, directory);
        } else if (std.mem.eql(u8, tag, "enum")) {
            try Enum.parse(self, parser);
        } else if (std.mem.eql(u8, tag, "xidtype")) {
            try self.parseXidType(parser);
        } else if (std.mem.eql(u8, tag, "xidunion")) {
            try XidUnion.parse(self, parser);
        } else if (std.mem.eql(u8, tag, "typedef")) {
            try self.parseTypedef(parser);
        } else if (std.mem.eql(u8, tag, "error")) {
            try Error.parse(self, parser);
        } else if (std.mem.eql(u8, tag, "struct")) {
            try Struct.parse(self, parser);
        } else if (std.mem.eql(u8, tag, "request")) {
            try Request.parse(self, parser);
        } else if (std.mem.eql(u8, tag, "event")) {
            try Event.parse(self, parser);
        } else if (std.mem.eql(u8, tag, "union")) {
            try Union.parse(self, parser);
        } else if (std.mem.eql(u8, tag, "eventstruct")) {
            try EventStruct.parse(self, parser);
        } else if (std.mem.endsWith(u8, tag, "copy")) {
            try Copy.parse(self, parser, tag[0..(tag.len - 4)]);
        },
        else => {},
    };
}

fn parseImport(self: *Protocol, parser: *xml.Parser, directory: std.fs.Dir) ParseError!void {
    const ev = parser.next() orelse return error.UnexpectedEndOfFile;
    if (ev != .character_data) return error.UnexpectedEvent;

    const name = try std.fmt.allocPrint(self.allocator, "{s}.xml", .{ev.character_data});
    errdefer self.allocator.free(name);

    var file = try directory.openFile(name, .{});
    defer file.close();

    const import = try create(self.allocator, .{
        .directory = directory,
        .source = file,
    });
    errdefer import.deinit();

    try self.imports.put(self.allocator, name, import);
}

fn parseXidType(self: *Protocol, parser: *xml.Parser) ParseError!void {
    const ev = parser.next() orelse return error.UnexpectedEndOfFile;
    if (ev != .attribute) return error.UnexpectedEvent;
    if (!std.mem.eql(u8, ev.attribute.name, "name")) return error.UnknownAttribute;

    const name = try ev.attribute.dupeValue(self.allocator);
    errdefer self.allocator.free(name);
    try self.xidtypes.append(self.allocator, name);
}

fn parseTypedef(self: *Protocol, parser: *xml.Parser) ParseError!void {
    const ev1 = parser.next() orelse return error.UnexpectedEndOfFile;
    if (ev1 != .attribute) return error.UnexpectedEvent;

    const ev2 = parser.next() orelse return error.UnexpectedEndOfFile;
    if (ev2 != .attribute) return error.UnexpectedEvent;

    if (std.mem.eql(u8, ev1.attribute.name, ev2.attribute.name)) return error.DuplicateAttributes;

    const old = if (std.mem.eql(u8, ev1.attribute.name, "oldname")) ev1.attribute else ev2.attribute;
    const new = if (std.mem.eql(u8, ev2.attribute.name, "newname")) ev2.attribute else ev1.attribute;

    std.debug.assert(std.mem.eql(u8, old.name, "oldname"));
    std.debug.assert(std.mem.eql(u8, new.name, "newname"));

    const oldname = try old.dupeValue(self.allocator);
    errdefer self.allocator.free(oldname);

    const newname = try new.dupeValue(self.allocator);
    errdefer self.allocator.free(newname);

    try self.typedefs.put(self.allocator, newname, oldname);
}

pub fn deinit(self: *Protocol) void {
    {
        var iter = self.imports.valueIterator();
        while (iter.next()) |import| deinit(import.*);
        self.imports.deinit(self.allocator);
    }

    for (self.enums.items) |*item| item.deinit(self.allocator);
    self.enums.deinit(self.allocator);

    for (self.xidtypes.items) |name| self.allocator.free(name);
    self.xidtypes.deinit(self.allocator);

    for (self.xidunions.items) |*item| item.deinit(self.allocator);
    self.xidunions.deinit(self.allocator);

    {
        var iter = self.typedefs.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.typedefs.deinit(self.allocator);
    }

    for (self.errors.items) |*err| err.deinit(self.allocator);
    self.errors.deinit(self.allocator);

    for (self.structs.items) |*str| str.deinit(self.allocator);
    self.structs.deinit(self.allocator);

    for (self.requests.items) |*req| req.deinit(self.allocator);
    self.requests.deinit(self.allocator);

    for (self.eventstructs.items) |*ev| ev.deinit(self.allocator);
    self.eventstructs.deinit(self.allocator);

    self.allocator.free(self.headerName);
    if (self.extName) |extName| self.allocator.free(extName);

    self.allocator.destroy(self);
}

pub fn endParse(self: *Protocol, parser: *xml.Parser, name: []const u8) !void {
    _ = self;

    while (true) {
        const ev = parser.next() orelse break;
        if (ev == .close_tag) {
            if (std.mem.eql(u8, ev.close_tag, name)) {
                return;
            }
        }
    }
    return error.UnexpectedEndOfFile;
}

pub fn generate(self: *const Protocol, generator: std.meta.DeclEnum(generators)) std.fmt.Formatter(fmtGenerate) {
    return .{ .data = .{ self, generator } };
}

fn fmtGenerate(data: struct { *const Protocol, std.meta.DeclEnum(generators) }, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    inline for (comptime std.meta.declarations(generators)) |decl| {
        if (std.mem.eql(u8, decl.name, @tagName(data[1]))) {
            return try @field(generators, decl.name).fmtProtocol(data[0], (options.width orelse 0) + 2, writer);
        }
    }
    unreachable;
}

pub fn generateSet(protos: []const *Protocol, generator: std.meta.DeclEnum(generators)) std.fmt.Formatter(fmtGenerateSet) {
    return .{ .data = .{ protos, generator } };
}

fn fmtGenerateSet(data: struct { []const *Protocol, std.meta.DeclEnum(generators) }, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    inline for (comptime std.meta.declarations(generators)) |decl| {
        if (std.mem.eql(u8, decl.name, @tagName(data[1]))) {
            return try @field(generators, decl.name).fmtProtocols(data[0], (options.width orelse 0) + 2, writer);
        }
    }
    unreachable;
}

test {
    _ = Copy;
    _ = Enum;
    _ = Error;
    _ = Event;
    _ = EventStruct;
    _ = Request;
    _ = Struct;
    _ = Union;
    _ = XidUnion;
}
