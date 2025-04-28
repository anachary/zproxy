const std = @import("std");
const logger = @import("../utils/logger.zig");
const http1 = @import("http1.zig");

/// WebSocket opcode
pub const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,
};

/// WebSocket frame header
pub const FrameHeader = struct {
    fin: bool,
    rsv1: bool,
    rsv2: bool,
    rsv3: bool,
    opcode: Opcode,
    mask: bool,
    payload_length: u64,
    mask_key: ?[4]u8,

    /// Parse a frame header from a buffer
    pub fn parse(buffer: []const u8) !struct { header: FrameHeader, bytes_read: usize } {
        if (buffer.len < 2) {
            return error.InsufficientData;
        }

        const byte1 = buffer[0];
        const byte2 = buffer[1];

        const fin = (byte1 & 0x80) != 0;
        const rsv1 = (byte1 & 0x40) != 0;
        const rsv2 = (byte1 & 0x20) != 0;
        const rsv3 = (byte1 & 0x10) != 0;
        const opcode = @as(Opcode, @enumFromInt(byte1 & 0x0F));

        const mask = (byte2 & 0x80) != 0;
        var payload_length: u64 = byte2 & 0x7F;

        var bytes_read: usize = 2;

        // Extended payload length
        if (payload_length == 126) {
            if (buffer.len < 4) {
                return error.InsufficientData;
            }

            payload_length = @as(u64, buffer[2]) << 8 | @as(u64, buffer[3]);
            bytes_read += 2;
        } else if (payload_length == 127) {
            if (buffer.len < 10) {
                return error.InsufficientData;
            }

            payload_length = @as(u64, buffer[2]) << 56 | @as(u64, buffer[3]) << 48 | @as(u64, buffer[4]) << 40 | @as(u64, buffer[5]) << 32 | @as(u64, buffer[6]) << 24 | @as(u64, buffer[7]) << 16 | @as(u64, buffer[8]) << 8 | @as(u64, buffer[9]);
            bytes_read += 8;
        }

        // Masking key
        var mask_key: ?[4]u8 = null;
        if (mask) {
            if (buffer.len < bytes_read + 4) {
                return error.InsufficientData;
            }

            mask_key = [4]u8{ buffer[bytes_read], buffer[bytes_read + 1], buffer[bytes_read + 2], buffer[bytes_read + 3] };
            bytes_read += 4;
        }

        return .{
            .header = FrameHeader{
                .fin = fin,
                .rsv1 = rsv1,
                .rsv2 = rsv2,
                .rsv3 = rsv3,
                .opcode = opcode,
                .mask = mask,
                .payload_length = payload_length,
                .mask_key = mask_key,
            },
            .bytes_read = bytes_read,
        };
    }

    /// Write a frame header to a buffer
    pub fn write(self: FrameHeader, buffer: []u8) !usize {
        if (buffer.len < 2) {
            return error.BufferTooSmall;
        }

        var bytes_written: usize = 2;

        // First byte
        buffer[0] = 0;
        if (self.fin) buffer[0] |= 0x80;
        if (self.rsv1) buffer[0] |= 0x40;
        if (self.rsv2) buffer[0] |= 0x20;
        if (self.rsv3) buffer[0] |= 0x10;
        buffer[0] |= @intFromEnum(self.opcode) & 0x0F;

        // Second byte
        buffer[1] = 0;
        if (self.mask) buffer[1] |= 0x80;

        // Payload length
        if (self.payload_length <= 125) {
            buffer[1] |= @intCast(self.payload_length & 0x7F);
        } else if (self.payload_length <= 65535) {
            if (buffer.len < 4) {
                return error.BufferTooSmall;
            }

            buffer[1] |= 126;
            buffer[2] = @intCast((self.payload_length >> 8) & 0xFF);
            buffer[3] = @intCast(self.payload_length & 0xFF);
            bytes_written += 2;
        } else {
            if (buffer.len < 10) {
                return error.BufferTooSmall;
            }

            buffer[1] |= 127;
            buffer[2] = @intCast((self.payload_length >> 56) & 0xFF);
            buffer[3] = @intCast((self.payload_length >> 48) & 0xFF);
            buffer[4] = @intCast((self.payload_length >> 40) & 0xFF);
            buffer[5] = @intCast((self.payload_length >> 32) & 0xFF);
            buffer[6] = @intCast((self.payload_length >> 24) & 0xFF);
            buffer[7] = @intCast((self.payload_length >> 16) & 0xFF);
            buffer[8] = @intCast((self.payload_length >> 8) & 0xFF);
            buffer[9] = @intCast(self.payload_length & 0xFF);
            bytes_written += 8;
        }

        // Masking key
        if (self.mask) {
            if (buffer.len < bytes_written + 4) {
                return error.BufferTooSmall;
            }

            if (self.mask_key) |key| {
                buffer[bytes_written] = key[0];
                buffer[bytes_written + 1] = key[1];
                buffer[bytes_written + 2] = key[2];
                buffer[bytes_written + 3] = key[3];
            } else {
                return error.MissingMaskKey;
            }

            bytes_written += 4;
        }

        return bytes_written;
    }
};

/// WebSocket connection
pub const WebSocketConnection = struct {
    stream: std.net.Stream,
    client_addr: std.net.Address,

    /// Initialize a new WebSocket connection
    pub fn init(stream: std.net.Stream, client_addr: std.net.Address) WebSocketConnection {
        return WebSocketConnection{
            .stream = stream,
            .client_addr = client_addr,
        };
    }

    /// Handle the connection
    pub fn handle(self: *WebSocketConnection, allocator: std.mem.Allocator, request: http1.Http1Request) !void {
        _ = allocator; // Unused in this implementation
        logger.debug("Handling WebSocket connection from {}", .{self.client_addr});

        // Verify WebSocket upgrade request
        if (!self.verifyUpgradeRequest(request)) {
            logger.err("Invalid WebSocket upgrade request from {}", .{self.client_addr});
            return error.InvalidUpgradeRequest;
        }

        // Send WebSocket upgrade response
        try self.sendUpgradeResponse();

        // Main frame processing loop
        var frame_buffer: [1024]u8 = undefined;

        while (true) {
            // Read frame header
            const header_bytes = try self.stream.read(frame_buffer[0..14]);
            if (header_bytes == 0) {
                // Connection closed
                break;
            }

            // Parse frame header
            const frame_result = try FrameHeader.parse(frame_buffer[0..header_bytes]);
            const frame_header = frame_result.header;
            const header_size = frame_result.bytes_read;

            // Read frame payload
            if (frame_header.payload_length > 0) {
                if (frame_header.payload_length > frame_buffer.len - header_size) {
                    logger.err("Frame payload too large from {}", .{self.client_addr});
                    return error.PayloadTooLarge;
                }

                var bytes_read: usize = 0;
                while (bytes_read < frame_header.payload_length) {
                    const read_size = try self.stream.read(frame_buffer[header_size + bytes_read .. header_size + @as(usize, @intCast(frame_header.payload_length))]);
                    if (read_size == 0) {
                        // Connection closed
                        return error.ConnectionClosed;
                    }
                    bytes_read += read_size;
                }

                // Unmask payload if needed
                if (frame_header.mask) {
                    if (frame_header.mask_key) |key| {
                        self.unmaskPayload(frame_buffer[header_size .. header_size + @as(usize, @intCast(frame_header.payload_length))], key);
                    }
                }
            }

            // Process frame
            try self.processFrame(frame_header, frame_buffer[header_size .. header_size + @as(usize, @intCast(frame_header.payload_length))]);

            // If this is a close frame, close the connection
            if (frame_header.opcode == .close) {
                break;
            }
        }
    }

    /// Verify WebSocket upgrade request
    fn verifyUpgradeRequest(self: *WebSocketConnection, request: http1.Http1Request) bool {
        _ = self;

        // Check for required headers
        const upgrade = request.headers.get("Upgrade") orelse return false;
        const connection = request.headers.get("Connection") orelse return false;
        const sec_websocket_key = request.headers.get("Sec-WebSocket-Key") orelse return false;
        const sec_websocket_version = request.headers.get("Sec-WebSocket-Version") orelse return false;

        // Verify header values
        if (!std.mem.eql(u8, std.mem.trim(u8, upgrade, " "), "websocket")) return false;
        if (!std.mem.containsAtLeast(u8, connection, 1, "upgrade")) return false;
        if (sec_websocket_key.len != 24) return false;
        if (!std.mem.eql(u8, sec_websocket_version, "13")) return false;

        return true;
    }

    /// Send WebSocket upgrade response
    fn sendUpgradeResponse(self: *WebSocketConnection) !void {
        const response =
            \\HTTP/1.1 101 Switching Protocols
            \\Upgrade: websocket
            \\Connection: Upgrade
            \\Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
            \\
            \\
        ;

        _ = try self.stream.write(response);
    }

    /// Unmask payload
    fn unmaskPayload(self: *WebSocketConnection, payload: []u8, mask_key: [4]u8) void {
        _ = self;

        for (payload, 0..) |_, i| {
            payload[i] ^= mask_key[i % 4];
        }
    }

    /// Process a frame
    fn processFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void {
        logger.debug("Processing frame: opcode={s}, fin={}, payload_length={d}", .{
            @tagName(header.opcode),
            header.fin,
            header.payload_length,
        });

        switch (header.opcode) {
            .text => try self.processTextFrame(header, payload),
            .binary => try self.processBinaryFrame(header, payload),
            .ping => try self.processPingFrame(header, payload),
            .pong => try self.processPongFrame(header, payload),
            .close => try self.processCloseFrame(header, payload),
            else => {
                logger.warning("Unhandled opcode: {s}", .{@tagName(header.opcode)});
            },
        }
    }

    /// Process a text frame
    fn processTextFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void {
        _ = header; // Unused in this implementation
        logger.debug("Received text message: {s}", .{payload});

        // Echo the message back
        try self.sendTextMessage(payload);
    }

    /// Process a binary frame
    fn processBinaryFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void {
        _ = header; // Unused in this implementation
        logger.debug("Received binary message, length={d}", .{payload.len});

        // Echo the message back
        try self.sendBinaryMessage(payload);
    }

    /// Process a ping frame
    fn processPingFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void {
        _ = header; // Unused in this implementation
        logger.debug("Received ping", .{});

        // Send pong with the same payload
        try self.sendPong(payload);
    }

    /// Process a pong frame
    fn processPongFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void {
        _ = header; // Unused in this implementation
        _ = payload; // Unused in this implementation
        _ = self; // Unused in this implementation
        logger.debug("Received pong", .{});

        // Nothing to do
    }

    /// Process a close frame
    fn processCloseFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void {
        _ = header; // Unused in this implementation
        _ = payload; // Unused in this implementation
        logger.debug("Received close frame", .{});

        // Send close frame
        try self.sendClose(1000, "Normal closure");
    }

    /// Send a text message
    pub fn sendTextMessage(self: *WebSocketConnection, message: []const u8) !void {
        var buffer: [1024]u8 = undefined;

        // Create frame header
        const header = FrameHeader{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .text,
            .mask = false,
            .payload_length = message.len,
            .mask_key = null,
        };

        // Write frame header
        const header_size = try header.write(&buffer);

        // Write payload
        @memcpy(buffer[header_size .. header_size + message.len], message);

        // Send frame
        _ = try self.stream.write(buffer[0 .. header_size + message.len]);
    }

    /// Send a binary message
    pub fn sendBinaryMessage(self: *WebSocketConnection, message: []const u8) !void {
        var buffer: [1024]u8 = undefined;

        // Create frame header
        const header = FrameHeader{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .binary,
            .mask = false,
            .payload_length = message.len,
            .mask_key = null,
        };

        // Write frame header
        const header_size = try header.write(&buffer);

        // Write payload
        @memcpy(buffer[header_size .. header_size + message.len], message);

        // Send frame
        _ = try self.stream.write(buffer[0 .. header_size + message.len]);
    }

    /// Send a ping
    pub fn sendPing(self: *WebSocketConnection, payload: []const u8) !void {
        var buffer: [1024]u8 = undefined;

        // Create frame header
        const header = FrameHeader{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .ping,
            .mask = false,
            .payload_length = payload.len,
            .mask_key = null,
        };

        // Write frame header
        const header_size = try header.write(&buffer);

        // Write payload
        @memcpy(buffer[header_size .. header_size + payload.len], payload);

        // Send frame
        _ = try self.stream.write(buffer[0 .. header_size + payload.len]);
    }

    /// Send a pong
    pub fn sendPong(self: *WebSocketConnection, payload: []const u8) !void {
        var buffer: [1024]u8 = undefined;

        // Create frame header
        const header = FrameHeader{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .pong,
            .mask = false,
            .payload_length = payload.len,
            .mask_key = null,
        };

        // Write frame header
        const header_size = try header.write(&buffer);

        // Write payload
        @memcpy(buffer[header_size .. header_size + payload.len], payload);

        // Send frame
        _ = try self.stream.write(buffer[0 .. header_size + payload.len]);
    }

    /// Send a close frame
    pub fn sendClose(self: *WebSocketConnection, code: u16, reason: []const u8) !void {
        var buffer: [1024]u8 = undefined;

        // Create payload (status code + reason)
        var payload: [2 + 123]u8 = undefined;
        payload[0] = @intCast((code >> 8) & 0xFF);
        payload[1] = @intCast(code & 0xFF);

        const reason_len = @min(reason.len, 123);
        @memcpy(payload[2 .. 2 + reason_len], reason[0..reason_len]);

        // Create frame header
        const header = FrameHeader{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .close,
            .mask = false,
            .payload_length = 2 + reason_len,
            .mask_key = null,
        };

        // Write frame header
        const header_size = try header.write(&buffer);

        // Write payload
        @memcpy(buffer[header_size .. header_size + 2 + reason_len], payload[0 .. 2 + reason_len]);

        // Send frame
        _ = try self.stream.write(buffer[0 .. header_size + 2 + reason_len]);
    }
};

/// Handle a WebSocket connection
pub fn handleConnection(allocator: std.mem.Allocator, stream: std.net.Stream, client_addr: std.net.Address, request: http1.Http1Request) !void {
    var connection = WebSocketConnection.init(stream, client_addr);
    try connection.handle(allocator, request);
}

test "WebSocket - Frame Header" {
    const testing = std.testing;

    // Create a frame header
    const header = FrameHeader{
        .fin = true,
        .rsv1 = false,
        .rsv2 = false,
        .rsv3 = false,
        .opcode = .text,
        .mask = true,
        .payload_length = 5,
        .mask_key = [4]u8{ 0x37, 0xfa, 0x21, 0x3d },
    };

    // Write to buffer
    var buffer: [14]u8 = undefined;
    const bytes_written = try header.write(&buffer);

    // Parse from buffer
    const parsed_result = try FrameHeader.parse(buffer[0..bytes_written]);
    const parsed = parsed_result.header;

    // Check values
    try testing.expect(parsed.fin);
    try testing.expect(!parsed.rsv1);
    try testing.expect(!parsed.rsv2);
    try testing.expect(!parsed.rsv3);
    try testing.expectEqual(Opcode.text, parsed.opcode);
    try testing.expect(parsed.mask);
    try testing.expectEqual(@as(u64, 5), parsed.payload_length);
    try testing.expectEqualSlices(u8, &[4]u8{ 0x37, 0xfa, 0x21, 0x3d }, parsed.mask_key.?);
}
