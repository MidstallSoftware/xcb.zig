const std = @import("std");
const xproto = @import("protos.zig").xproto;

pub const GenericReply = extern struct {
    response_type: u8,
    pad0: u8,
    sequence: u16,
    length: u32,
};

pub const GenericEvent = extern struct {
    response_type: u8,
    pad0: u8,
    sequence: u16,
    pad: [7]u32,
    full_sequence: u32,
};

pub const RawGenericEvent = extern struct {
    response_type: u8,
    pad0: u8,
    sequence: u16,
    pad: [7]u32,
};

pub const GeEvent = extern struct {
    response_type: u8,
    pad0: u8,
    sequence: u16,
    length: u32,
    event_type: u16,
    pad1: u16,
    pad: [5]u32,
    full_sequence: u32,
};

pub const GenericError = extern struct {
    response_type: u8,
    error_code: u8,
    sequence: u16,
    resource_id: u32,
    minor_code: u16,
    major_code: u8,
    pad0: u8,
    pad: [5]u32,
    full_sequence: u32,
};

pub const VoidCookie = extern struct {
    seq: c_uint,
};

pub const AuthInfo = extern struct {
    namelen: c_int,
    name: [*:0]u8,
    datalen: c_int,
    data: [*:0]u8,
};

pub const SpecialEvent = opaque {};
pub const Extension = opaque {};

pub const Connection = extern struct {
    const Impl = opaque {};

    impl: *const Impl,

    extern fn xcb_flush(*Connection) c_int;
    pub fn flush(self: *Connection) !void {
        return switch (std.c.getErrno(xcb_flush(self))) {
            else => |err| std.os.unexpectedErrno(err),
        };
    }

    extern fn xcb_get_maximum_request_length(*Connection) u32;
    pub const getMaximumRequestLength = xcb_get_maximum_request_length;

    extern fn xcb_prefetch_maximum_request_length(*Connection) void;
    pub const prefetchMaximumRequestLength = xcb_prefetch_maximum_request_length;

    extern fn xcb_wait_for_event(*Connection) ?*GenericEvent;
    pub fn waitForEvent(self: *Connection) !*GenericEvent {
        return xcb_wait_for_event(self) orelse error.IoFailure;
    }

    extern fn xcb_poll_for_event(*Connection) ?*GenericEvent;
    pub const pollForEvent = xcb_poll_for_event;

    extern fn xcb_poll_for_queued_event(*Connection) ?*GenericEvent;
    pub const pollForQueuedEvent = xcb_poll_for_queued_event;

    extern fn xcb_poll_for_special_event(*Connection, *SpecialEvent) ?*GenericEvent;
    pub const pollForSpecialEvent = xcb_poll_for_special_event;

    extern fn xcb_wait_for_special_event(*Connection, *SpecialEvent) ?*GenericEvent;
    pub fn waitForSpecialEvent(self: *Connection, se: *SpecialEvent) !*GenericEvent {
        return xcb_wait_for_special_event(self, se) orelse error.IoFailure;
    }

    extern fn xcb_register_for_special_xge(*Connection, *Extension, u32, *u32) *SpecialEvent;
    pub const registerForSpecialXge = xcb_register_for_special_xge;

    extern fn xcb_unregister_for_special_event(*Connection, *SpecialEvent) void;
    pub const unregisterForSpecialEvent = xcb_unregister_for_special_event;

    extern fn xcb_request_check(*Connection, VoidCookie) ?*GenericError;
    pub const requestCheck = xcb_request_check;

    extern fn xcb_discard_reply(*Connection, c_uint) void;
    pub const discardReply = xcb_discard_reply;

    extern fn xcb_discard_reply64(*Connection, u64) void;
    pub const discardReply64 = xcb_discard_reply64;

    extern fn xcb_get_extension_data(*Connection, *Extension) *xproto.QueryExtensionReply;
    pub const getExtensionData = xcb_get_extension_data;

    extern fn xcb_prefetch_extension_data(*Connection, *Extension) void;
    pub const prefetchExtensionData = xcb_prefetch_extension_data;

    extern fn xcb_get_setup(*Connection) *xproto.Setup;
    pub const getSetup = xcb_get_setup;

    extern fn xcb_get_file_descriptor(*Connection) c_int;
    pub const getFileDescriptor = xcb_get_file_descriptor;

    extern fn xcb_connect_to_fd(c_int, ?*AuthInfo) ?*Connection;
    pub fn connectToFd(fd: c_int, auth: ?*AuthInfo) !*Connection {
        return xcb_connect_to_fd(fd, auth) orelse error.ConnectionFailed;
    }

    extern fn xcb_disconnect(*Connection) void;
    pub const disconnect = xcb_disconnect;

    extern fn xcb_connect(?[*:0]u8, ?*c_int) ?*Connection;
    pub fn connect(display: ?[*:0]u8, pscrn: ?*c_int) !*Connection {
        return xcb_connect(display, pscrn) orelse error.ConnectionFailed;
    }

    extern fn xcb_connect_to_display_with_auth_info([*:0]u8, *AuthInfo, ?*c_int) ?*Connection;
    pub fn connectToDisplayWithAuthInfo(display: [*:0]u8, auth: *AuthInfo, pscrn: ?*c_int) !*Connection {
        return xcb_connect_to_display_with_auth_info(display, auth, pscrn) orelse error.ConnectionFailed;
    }

    extern fn xcb_generate_id(*Connection) u32;
    pub fn generateId(self: *Connection) !u32 {
        const id = xcb_generate_id(self);
        return if (id == -1) error.InvalidResource else id;
    }

    extern fn xcb_total_read(*Connection) u64;
    pub const totalRead = xcb_total_read;

    extern fn xcb_total_write(*Connection) u64;
    pub const totalWrite = xcb_total_write;
};
