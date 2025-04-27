const std = @import("std");

/// HTTP/2 frame types
pub const FrameType = enum(u8) {
    DATA = 0x0,
    HEADERS = 0x1,
    PRIORITY = 0x2,
    RST_STREAM = 0x3,
    SETTINGS = 0x4,
    PUSH_PROMISE = 0x5,
    PING = 0x6,
    GOAWAY = 0x7,
    WINDOW_UPDATE = 0x8,
    CONTINUATION = 0x9,
    _,
};

/// HTTP/2 frame flags
pub const FrameFlags = struct {
    pub const END_STREAM = 0x1;
    pub const ACK = 0x1;
    pub const END_HEADERS = 0x4;
    pub const PADDED = 0x8;
    pub const PRIORITY = 0x20;
};

/// HTTP/2 error codes
pub const ErrorCode = enum(u32) {
    NO_ERROR = 0x0,
    PROTOCOL_ERROR = 0x1,
    INTERNAL_ERROR = 0x2,
    FLOW_CONTROL_ERROR = 0x3,
    SETTINGS_TIMEOUT = 0x4,
    STREAM_CLOSED = 0x5,
    FRAME_SIZE_ERROR = 0x6,
    REFUSED_STREAM = 0x7,
    CANCEL = 0x8,
    COMPRESSION_ERROR = 0x9,
    CONNECT_ERROR = 0xa,
    ENHANCE_YOUR_CALM = 0xb,
    INADEQUATE_SECURITY = 0xc,
    HTTP_1_1_REQUIRED = 0xd,
    _,
};

/// HTTP/2 frame header
pub const FrameHeader = struct {
    length: u24,
    type: FrameType,
    flags: u8,
    stream_id: u31,
    reserved: u1,
};

/// HTTP/2 frame
pub const Frame = struct {
    header: FrameHeader,
    payload: []const u8,
};

/// HTTP/2 header field
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// HTTP/2 settings
pub const Settings = struct {
    header_table_size: ?u32 = null,
    enable_push: ?bool = null,
    max_concurrent_streams: ?u32 = null,
    initial_window_size: ?u32 = null,
    max_frame_size: ?u32 = null,
    max_header_list_size: ?u32 = null,
};

/// HTTP/2 connection state
pub const Connection = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    buffer: []u8,
    settings: Settings,

    /// Initialize a new HTTP/2 connection
    pub fn init(allocator: std.mem.Allocator, stream: std.net.Stream) !Connection {
        const buffer = try allocator.alloc(u8, 16384);
        return Connection{
            .allocator = allocator,
            .stream = stream,
            .buffer = buffer,
            .settings = Settings{},
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Connection) void {
        self.allocator.free(self.buffer);
    }

    /// Read a frame from the connection
    pub fn readFrame(self: *Connection) !Frame {
        // Read the 9-byte frame header
        const header_size = 9;
        const bytes_read = try self.stream.read(self.buffer[0..header_size]);
        if (bytes_read < header_size) {
            return error.EndOfStream;
        }

        // Parse the frame header
        const length = @as(u24, @intCast(self.buffer[0])) << 16 |
            @as(u24, @intCast(self.buffer[1])) << 8 |
            @as(u24, @intCast(self.buffer[2]));

        const frame_type = @as(FrameType, @enumFromInt(self.buffer[3]));
        const flags = self.buffer[4];

        const reserved = @as(u1, @intCast((self.buffer[5] & 0x80) >> 7));
        const stream_id = @as(u31, @intCast((@as(u32, @intCast(self.buffer[5] & 0x7f)) << 24) |
            (@as(u32, @intCast(self.buffer[6])) << 16) |
            (@as(u32, @intCast(self.buffer[7])) << 8) |
            @as(u32, @intCast(self.buffer[8]))));

        const header = FrameHeader{
            .length = length,
            .type = frame_type,
            .flags = flags,
            .stream_id = stream_id,
            .reserved = reserved,
        };

        // Read the frame payload
        if (length > 0) {
            if (length > self.buffer.len) {
                return error.FrameTooLarge;
            }

            const payload_bytes_read = try self.stream.read(self.buffer[0..length]);
            if (payload_bytes_read < length) {
                return error.IncompleteFrame;
            }

            const payload = try self.allocator.dupe(u8, self.buffer[0..length]);
            return Frame{
                .header = header,
                .payload = payload,
            };
        } else {
            return Frame{
                .header = header,
                .payload = &[_]u8{},
            };
        }
    }

    /// Send a SETTINGS frame
    pub fn sendSettings(self: *Connection, settings: Settings) !void {
        var payload = std.ArrayList(u8).init(self.allocator);
        defer payload.deinit();

        // Add settings to payload
        if (settings.header_table_size) |size| {
            try payload.appendSlice(&[_]u8{ 0x00, 0x01 });
            try payload.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u32, size)));
        }

        if (settings.enable_push) |enable| {
            try payload.appendSlice(&[_]u8{ 0x00, 0x02 });
            try payload.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u32, @intFromBool(enable))));
        }

        if (settings.max_concurrent_streams) |max| {
            try payload.appendSlice(&[_]u8{ 0x00, 0x03 });
            try payload.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u32, max)));
        }

        if (settings.initial_window_size) |size| {
            try payload.appendSlice(&[_]u8{ 0x00, 0x04 });
            try payload.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u32, size)));
        }

        if (settings.max_frame_size) |size| {
            try payload.appendSlice(&[_]u8{ 0x00, 0x05 });
            try payload.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u32, size)));
        }

        if (settings.max_header_list_size) |size| {
            try payload.appendSlice(&[_]u8{ 0x00, 0x06 });
            try payload.appendSlice(&std.mem.toBytes(std.mem.nativeToBig(u32, size)));
        }

        // Send the frame
        try self.sendFrame(.{
            .length = @intCast(payload.items.len),
            .type = .SETTINGS,
            .flags = 0,
            .stream_id = 0,
            .reserved = 0,
        }, payload.items);
    }

    /// Send a SETTINGS ACK frame
    pub fn sendSettingsAck(self: *Connection) !void {
        try self.sendFrame(.{
            .length = 0,
            .type = .SETTINGS,
            .flags = FrameFlags.ACK,
            .stream_id = 0,
            .reserved = 0,
        }, &[_]u8{});
    }

    /// Send a PING ACK frame
    pub fn sendPingAck(self: *Connection, payload: []const u8) !void {
        try self.sendFrame(.{
            .length = @intCast(payload.len),
            .type = .PING,
            .flags = FrameFlags.ACK,
            .stream_id = 0,
            .reserved = 0,
        }, payload);
    }

    /// Send a RST_STREAM frame
    pub fn sendRstStream(self: *Connection, stream_id: u31, error_code: ErrorCode) !void {
        const error_code_bytes = std.mem.toBytes(std.mem.nativeToBig(u32, @intFromEnum(error_code)));
        try self.sendFrame(.{
            .length = 4,
            .type = .RST_STREAM,
            .flags = 0,
            .stream_id = stream_id,
            .reserved = 0,
        }, &error_code_bytes);
    }

    /// Send a HEADERS frame
    pub fn sendHeaders(self: *Connection, stream_id: u31, headers: []const Header, end_stream: bool) !void {
        // Encode headers (simplified - in a real implementation, use HPACK)
        var encoded = std.ArrayList(u8).init(self.allocator);
        defer encoded.deinit();

        for (headers) |header| {
            // Very simplified header encoding - not HPACK compliant
            try encoded.appendSlice(header.name);
            try encoded.append(':');
            try encoded.appendSlice(header.value);
            try encoded.append(0);
        }

        // Set flags
        var flags: u8 = FrameFlags.END_HEADERS;
        if (end_stream) {
            flags |= FrameFlags.END_STREAM;
        }

        // Send the frame
        try self.sendFrame(.{
            .length = @intCast(encoded.items.len),
            .type = .HEADERS,
            .flags = flags,
            .stream_id = stream_id,
            .reserved = 0,
        }, encoded.items);
    }

    /// Send a DATA frame
    pub fn sendData(self: *Connection, stream_id: u31, data: []const u8, end_stream: bool) !void {
        var flags: u8 = 0;
        if (end_stream) {
            flags |= FrameFlags.END_STREAM;
        }

        try self.sendFrame(.{
            .length = @intCast(data.len),
            .type = .DATA,
            .flags = flags,
            .stream_id = stream_id,
            .reserved = 0,
        }, data);
    }

    /// Send a frame
    fn sendFrame(self: *Connection, header: FrameHeader, payload: []const u8) !void {
        // Encode the frame header
        var header_bytes: [9]u8 = undefined;

        // Length (24 bits)
        header_bytes[0] = @intCast((header.length >> 16) & 0xff);
        header_bytes[1] = @intCast((header.length >> 8) & 0xff);
        header_bytes[2] = @intCast(header.length & 0xff);

        // Type (8 bits)
        header_bytes[3] = @intFromEnum(header.type);

        // Flags (8 bits)
        header_bytes[4] = header.flags;

        // Reserved bit (1 bit) and Stream ID (31 bits)
        const reserved_bit: u8 = if (header.reserved == 1) 0x80 else 0;
        const stream_id_high: u8 = @intCast((header.stream_id >> 24) & 0x7f);
        header_bytes[5] = reserved_bit | stream_id_high;
        header_bytes[6] = @intCast((header.stream_id >> 16) & 0xff);
        header_bytes[7] = @intCast((header.stream_id >> 8) & 0xff);
        header_bytes[8] = @intCast(header.stream_id & 0xff);

        // Send the header
        _ = try self.stream.write(&header_bytes);

        // Send the payload
        if (payload.len > 0) {
            _ = try self.stream.write(payload);
        }
    }

    /// Apply settings received from peer
    pub fn applySettings(self: *Connection, settings: Settings) void {
        if (settings.header_table_size) |size| {
            self.settings.header_table_size = size;
        }

        if (settings.enable_push) |enable| {
            self.settings.enable_push = enable;
        }

        if (settings.max_concurrent_streams) |max| {
            self.settings.max_concurrent_streams = max;
        }

        if (settings.initial_window_size) |size| {
            self.settings.initial_window_size = size;
        }

        if (settings.max_frame_size) |size| {
            self.settings.max_frame_size = size;
        }

        if (settings.max_header_list_size) |size| {
            self.settings.max_header_list_size = size;
        }
    }
};

/// Parse HTTP/2 SETTINGS frame payload
pub fn parseSettings(payload: []const u8) !Settings {
    var settings = Settings{};
    var i: usize = 0;

    while (i + 6 <= payload.len) {
        const identifier = @as(u16, @intCast(payload[i])) << 8 | @as(u16, @intCast(payload[i + 1]));
        var value_bytes: [4]u8 = undefined;
        @memcpy(&value_bytes, payload[i + 2 .. i + 6]);
        const value = std.mem.readIntBig(u32, &value_bytes);

        switch (identifier) {
            0x1 => settings.header_table_size = value,
            0x2 => settings.enable_push = value != 0,
            0x3 => settings.max_concurrent_streams = value,
            0x4 => settings.initial_window_size = value,
            0x5 => settings.max_frame_size = value,
            0x6 => settings.max_header_list_size = value,
            else => {}, // Ignore unknown settings
        }

        i += 6;
    }

    return settings;
}

/// Parse HTTP/2 headers (simplified - not using HPACK)
pub fn parseHeaders(allocator: std.mem.Allocator, payload: []const u8) ![]Header {
    // This is a very simplified implementation
    // In a real implementation, use HPACK decoding

    var headers = std.ArrayList(Header).init(allocator);
    defer headers.deinit();

    var i: usize = 0;
    while (i < payload.len) {
        // Find the name
        const name_start = i;
        while (i < payload.len and payload[i] != ':') {
            i += 1;
        }

        if (i >= payload.len) {
            break;
        }

        const name = try allocator.dupe(u8, payload[name_start..i]);
        i += 1; // Skip ':'

        // Find the value
        const value_start = i;
        while (i < payload.len and payload[i] != 0) {
            i += 1;
        }

        const value = try allocator.dupe(u8, payload[value_start..i]);
        i += 1; // Skip null terminator

        try headers.append(Header{
            .name = name,
            .value = value,
        });
    }

    return headers.toOwnedSlice();
}
