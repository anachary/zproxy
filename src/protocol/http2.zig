const std = @import("std");
const logger = @import("../utils/logger.zig");

/// HTTP/2 frame types
pub const FrameType = enum(u8) {
    data = 0x0,
    headers = 0x1,
    priority = 0x2,
    rst_stream = 0x3,
    settings = 0x4,
    push_promise = 0x5,
    ping = 0x6,
    goaway = 0x7,
    window_update = 0x8,
    continuation = 0x9,
};

/// HTTP/2 frame flags
pub const FrameFlags = struct {
    end_stream: bool = false,
    end_headers: bool = false,
    padded: bool = false,
    priority: bool = false,
    ack: bool = false,

    /// Convert flags to a byte
    pub fn toByte(self: FrameFlags) u8 {
        var result: u8 = 0;
        if (self.end_stream) result |= 0x1;
        if (self.end_headers) result |= 0x4;
        if (self.padded) result |= 0x8;
        if (self.priority) result |= 0x20;
        if (self.ack) result |= 0x1;
        return result;
    }

    /// Parse flags from a byte
    pub fn fromByte(byte: u8, frame_type: FrameType) FrameFlags {
        return switch (frame_type) {
            .data => .{
                .end_stream = (byte & 0x1) != 0,
                .padded = (byte & 0x8) != 0,
            },
            .headers => .{
                .end_stream = (byte & 0x1) != 0,
                .end_headers = (byte & 0x4) != 0,
                .padded = (byte & 0x8) != 0,
                .priority = (byte & 0x20) != 0,
            },
            .settings => .{
                .ack = (byte & 0x1) != 0,
            },
            .ping => .{
                .ack = (byte & 0x1) != 0,
            },
            else => .{},
        };
    }
};

/// HTTP/2 frame header
pub const FrameHeader = struct {
    length: u24,
    type: FrameType,
    flags: FrameFlags,
    stream_id: u31,

    /// Parse a frame header from a buffer
    pub fn parse(buffer: []const u8) !FrameHeader {
        if (buffer.len < 9) {
            return error.InvalidFrameHeader;
        }

        const length = @as(u24, buffer[0]) << 16 | @as(u24, buffer[1]) << 8 | @as(u24, buffer[2]);
        const frame_type = @as(FrameType, @enumFromInt(buffer[3]));
        const flags_byte = buffer[4];
        const stream_id = @as(u31, buffer[5] & 0x7F) << 24 | @as(u31, buffer[6]) << 16 | @as(u31, buffer[7]) << 8 | @as(u31, buffer[8]);

        return FrameHeader{
            .length = length,
            .type = frame_type,
            .flags = FrameFlags.fromByte(flags_byte, frame_type),
            .stream_id = stream_id,
        };
    }

    /// Write a frame header to a buffer
    pub fn write(self: FrameHeader, buffer: []u8) !void {
        if (buffer.len < 9) {
            return error.BufferTooSmall;
        }

        buffer[0] = @intCast((self.length >> 16) & 0xFF);
        buffer[1] = @intCast((self.length >> 8) & 0xFF);
        buffer[2] = @intCast(self.length & 0xFF);
        buffer[3] = @intFromEnum(self.type);
        buffer[4] = self.flags.toByte();
        buffer[5] = @intCast(((self.stream_id >> 24) & 0x7F));
        buffer[6] = @intCast((self.stream_id >> 16) & 0xFF);
        buffer[7] = @intCast((self.stream_id >> 8) & 0xFF);
        buffer[8] = @intCast(self.stream_id & 0xFF);
    }
};

/// HTTP/2 settings
pub const Settings = struct {
    header_table_size: u32 = 4096,
    enable_push: bool = true,
    max_concurrent_streams: u32 = 100,
    initial_window_size: u32 = 65535,
    max_frame_size: u32 = 16384,
    max_header_list_size: u32 = 65536,
};

/// HTTP/2 connection
pub const Http2Connection = struct {
    stream: std.net.Stream,
    client_addr: std.net.Address,
    settings: Settings,

    /// Initialize a new HTTP/2 connection
    pub fn init(stream: std.net.Stream, client_addr: std.net.Address) Http2Connection {
        return Http2Connection{
            .stream = stream,
            .client_addr = client_addr,
            .settings = Settings{},
        };
    }

    /// Handle the connection
    pub fn handle(self: *Http2Connection) !void {
        logger.debug("Handling HTTP/2 connection from {}", .{self.client_addr});

        // Read the connection preface
        var preface_buffer: [24]u8 = undefined;
        const preface_bytes = try self.stream.read(&preface_buffer);

        if (preface_bytes != 24 or !std.mem.eql(u8, &preface_buffer, "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")) {
            logger.err("Invalid HTTP/2 preface from {}", .{self.client_addr});
            return error.InvalidPreface;
        }

        // Send initial settings
        try self.sendSettings();

        // Main frame processing loop
        var frame_header_buffer: [9]u8 = undefined;
        var frame_payload_buffer: [16384]u8 = undefined;

        while (true) {
            // Read frame header
            const header_bytes = try self.stream.read(&frame_header_buffer);
            if (header_bytes == 0) {
                // Connection closed
                break;
            }

            if (header_bytes != 9) {
                logger.err("Incomplete frame header from {}", .{self.client_addr});
                return error.IncompleteFrameHeader;
            }

            // Parse frame header
            const frame_header = try FrameHeader.parse(&frame_header_buffer);

            // Read frame payload
            if (frame_header.length > 0) {
                if (frame_header.length > self.settings.max_frame_size) {
                    logger.err("Frame too large from {}", .{self.client_addr});
                    return error.FrameTooLarge;
                }

                var bytes_read: usize = 0;
                while (bytes_read < frame_header.length) {
                    const read_size = try self.stream.read(frame_payload_buffer[bytes_read..frame_header.length]);
                    if (read_size == 0) {
                        // Connection closed
                        return error.ConnectionClosed;
                    }
                    bytes_read += read_size;
                }
            }

            // Process frame
            try self.processFrame(frame_header, frame_payload_buffer[0..frame_header.length]);
        }
    }

    /// Send settings frame
    fn sendSettings(self: *Http2Connection) !void {
        // Create settings frame
        var settings_buffer: [9 + 6 * 6]u8 = undefined;

        // Frame header
        const header = FrameHeader{
            .length = 6 * 6, // 6 settings, 6 bytes each
            .type = .settings,
            .flags = .{},
            .stream_id = 0,
        };

        try header.write(settings_buffer[0..9]);

        // Settings payload
        var offset: usize = 9;

        // SETTINGS_HEADER_TABLE_SIZE
        settings_buffer[offset] = 0x0;
        settings_buffer[offset + 1] = 0x1;
        settings_buffer[offset + 2] = @intCast((self.settings.header_table_size >> 24) & 0xFF);
        settings_buffer[offset + 3] = @intCast((self.settings.header_table_size >> 16) & 0xFF);
        settings_buffer[offset + 4] = @intCast((self.settings.header_table_size >> 8) & 0xFF);
        settings_buffer[offset + 5] = @intCast(self.settings.header_table_size & 0xFF);
        offset += 6;

        // SETTINGS_ENABLE_PUSH
        settings_buffer[offset] = 0x0;
        settings_buffer[offset + 1] = 0x2;
        settings_buffer[offset + 2] = 0x0;
        settings_buffer[offset + 3] = 0x0;
        settings_buffer[offset + 4] = 0x0;
        settings_buffer[offset + 5] = if (self.settings.enable_push) 0x1 else 0x0;
        offset += 6;

        // SETTINGS_MAX_CONCURRENT_STREAMS
        settings_buffer[offset] = 0x0;
        settings_buffer[offset + 1] = 0x3;
        settings_buffer[offset + 2] = @intCast((self.settings.max_concurrent_streams >> 24) & 0xFF);
        settings_buffer[offset + 3] = @intCast((self.settings.max_concurrent_streams >> 16) & 0xFF);
        settings_buffer[offset + 4] = @intCast((self.settings.max_concurrent_streams >> 8) & 0xFF);
        settings_buffer[offset + 5] = @intCast(self.settings.max_concurrent_streams & 0xFF);
        offset += 6;

        // SETTINGS_INITIAL_WINDOW_SIZE
        settings_buffer[offset] = 0x0;
        settings_buffer[offset + 1] = 0x4;
        settings_buffer[offset + 2] = @intCast((self.settings.initial_window_size >> 24) & 0xFF);
        settings_buffer[offset + 3] = @intCast((self.settings.initial_window_size >> 16) & 0xFF);
        settings_buffer[offset + 4] = @intCast((self.settings.initial_window_size >> 8) & 0xFF);
        settings_buffer[offset + 5] = @intCast(self.settings.initial_window_size & 0xFF);
        offset += 6;

        // SETTINGS_MAX_FRAME_SIZE
        settings_buffer[offset] = 0x0;
        settings_buffer[offset + 1] = 0x5;
        settings_buffer[offset + 2] = @intCast((self.settings.max_frame_size >> 24) & 0xFF);
        settings_buffer[offset + 3] = @intCast((self.settings.max_frame_size >> 16) & 0xFF);
        settings_buffer[offset + 4] = @intCast((self.settings.max_frame_size >> 8) & 0xFF);
        settings_buffer[offset + 5] = @intCast(self.settings.max_frame_size & 0xFF);
        offset += 6;

        // SETTINGS_MAX_HEADER_LIST_SIZE
        settings_buffer[offset] = 0x0;
        settings_buffer[offset + 1] = 0x6;
        settings_buffer[offset + 2] = @intCast((self.settings.max_header_list_size >> 24) & 0xFF);
        settings_buffer[offset + 3] = @intCast((self.settings.max_header_list_size >> 16) & 0xFF);
        settings_buffer[offset + 4] = @intCast((self.settings.max_header_list_size >> 8) & 0xFF);
        settings_buffer[offset + 5] = @intCast(self.settings.max_header_list_size & 0xFF);

        // Send settings frame
        _ = try self.stream.write(&settings_buffer);
    }

    /// Process a frame
    fn processFrame(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void {
        logger.debug("Processing frame: type={s}, length={d}, stream_id={d}", .{
            @tagName(header.type),
            header.length,
            header.stream_id,
        });

        switch (header.type) {
            .settings => try self.processSettings(header, payload),
            .headers => try self.processHeaders(header, payload),
            .data => try self.processData(header, payload),
            .ping => try self.processPing(header, payload),
            .goaway => try self.processGoaway(header, payload),
            else => {
                logger.warning("Unhandled frame type: {s}", .{@tagName(header.type)});
            },
        }
    }

    /// Process a settings frame
    fn processSettings(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void {
        if (header.flags.ack) {
            // Settings acknowledgement
            logger.debug("Received settings acknowledgement", .{});
            return;
        }

        // Parse settings
        var offset: usize = 0;
        while (offset + 6 <= payload.len) {
            const identifier = @as(u16, payload[offset]) << 8 | @as(u16, payload[offset + 1]);
            const value = @as(u32, payload[offset + 2]) << 24 | @as(u32, payload[offset + 3]) << 16 | @as(u32, payload[offset + 4]) << 8 | @as(u32, payload[offset + 5]);

            switch (identifier) {
                0x1 => self.settings.header_table_size = value,
                0x2 => self.settings.enable_push = value != 0,
                0x3 => self.settings.max_concurrent_streams = value,
                0x4 => self.settings.initial_window_size = value,
                0x5 => self.settings.max_frame_size = value,
                0x6 => self.settings.max_header_list_size = value,
                else => {
                    logger.warning("Unknown settings identifier: {d}", .{identifier});
                },
            }

            offset += 6;
        }

        // Send settings acknowledgement
        var ack_buffer: [9]u8 = undefined;
        const ack_header = FrameHeader{
            .length = 0,
            .type = .settings,
            .flags = .{ .ack = true },
            .stream_id = 0,
        };

        try ack_header.write(&ack_buffer);
        _ = try self.stream.write(&ack_buffer);
    }

    /// Process a headers frame
    fn processHeaders(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void {
        _ = payload; // Unused in this implementation
        // This is a simplified implementation
        logger.debug("Received headers frame for stream {d}", .{header.stream_id});

        // Send a response (simplified)
        try self.sendResponse(header.stream_id);
    }

    /// Process a data frame
    fn processData(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void {
        _ = self; // Unused in this implementation
        logger.debug("Received data frame for stream {d}, length={d}", .{ header.stream_id, payload.len });

        // In a real implementation, we would process the data
    }

    /// Process a ping frame
    fn processPing(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void {
        if (header.flags.ack) {
            // Ping acknowledgement
            logger.debug("Received ping acknowledgement", .{});
            return;
        }

        // Send ping acknowledgement
        var ping_buffer: [9 + 8]u8 = undefined;
        const ping_header = FrameHeader{
            .length = 8,
            .type = .ping,
            .flags = .{ .ack = true },
            .stream_id = 0,
        };

        try ping_header.write(ping_buffer[0..9]);

        // Copy ping payload
        @memcpy(ping_buffer[9..17], payload[0..8]);

        _ = try self.stream.write(&ping_buffer);
    }

    /// Process a goaway frame
    fn processGoaway(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void {
        _ = self; // Unused in this implementation
        _ = header; // Unused in this implementation
        if (payload.len < 8) {
            logger.err("Invalid goaway frame", .{});
            return error.InvalidGoawayFrame;
        }

        const last_stream_id = @as(u31, payload[0] & 0x7F) << 24 | @as(u31, payload[1]) << 16 | @as(u31, payload[2]) << 8 | @as(u31, payload[3]);
        const error_code = @as(u32, payload[4]) << 24 | @as(u32, payload[5]) << 16 | @as(u32, payload[6]) << 8 | @as(u32, payload[7]);

        logger.debug("Received goaway frame: last_stream_id={d}, error_code={d}", .{ last_stream_id, error_code });

        // In a real implementation, we would close the connection
    }

    /// Send a response (simplified)
    fn sendResponse(self: *Http2Connection, stream_id: u31) !void {
        // This is a simplified implementation that sends a basic response

        // Headers frame
        var headers_buffer: [9 + 100]u8 = undefined;
        const headers_header = FrameHeader{
            .length = 100, // Simplified
            .type = .headers,
            .flags = .{ .end_headers = true },
            .stream_id = stream_id,
        };

        try headers_header.write(headers_buffer[0..9]);

        // Simplified headers encoding (this would normally use HPACK)
        const headers = ":status: 200\r\ncontent-type: text/plain\r\n\r\n";
        @memcpy(headers_buffer[9 .. 9 + headers.len], headers);

        _ = try self.stream.write(headers_buffer[0 .. 9 + headers.len]);

        // Data frame
        var data_buffer: [9 + 13]u8 = undefined;
        const data_header = FrameHeader{
            .length = 13,
            .type = .data,
            .flags = .{ .end_stream = true },
            .stream_id = stream_id,
        };

        try data_header.write(data_buffer[0..9]);

        // Response body
        const body = "Hello, HTTP/2!";
        @memcpy(data_buffer[9 .. 9 + body.len], body);

        _ = try self.stream.write(&data_buffer);
    }
};

/// Handle an HTTP/2 connection
pub fn handleConnection(stream: std.net.Stream, client_addr: std.net.Address) !void {
    var connection = Http2Connection.init(stream, client_addr);
    try connection.handle();
}

test "HTTP/2 - Frame Header" {
    const testing = std.testing;

    // Create a frame header
    const header = FrameHeader{
        .length = 16,
        .type = .headers,
        .flags = .{ .end_headers = true, .end_stream = true },
        .stream_id = 1,
    };

    // Write to buffer
    var buffer: [9]u8 = undefined;
    try header.write(&buffer);

    // Parse from buffer
    const parsed = try FrameHeader.parse(&buffer);

    // Check values
    try testing.expectEqual(@as(u24, 16), parsed.length);
    try testing.expectEqual(FrameType.headers, parsed.type);
    try testing.expect(parsed.flags.end_headers);
    try testing.expect(parsed.flags.end_stream);
    try testing.expectEqual(@as(u31, 1), parsed.stream_id);
}
