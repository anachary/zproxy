const std = @import("std");

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

/// WebSocket frame
pub const Frame = struct {
    fin: bool,
    rsv1: bool,
    rsv2: bool,
    rsv3: bool,
    opcode: Opcode,
    mask: bool,
    payload_length: u64,
    mask_key: ?[4]u8,
    payload: []const u8,
    
    /// Clean up resources
    pub fn deinit(self: *Frame, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
    }
};

/// WebSocket connection
pub const Connection = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    buffer: []u8,
    
    /// Initialize a new WebSocket connection
    pub fn init(allocator: std.mem.Allocator, stream: std.net.Stream) !Connection {
        const buffer = try allocator.alloc(u8, 65536);
        return Connection{
            .allocator = allocator,
            .stream = stream,
            .buffer = buffer,
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *Connection) void {
        self.allocator.free(self.buffer);
    }
    
    /// Read a frame from the connection
    pub fn readFrame(self: *Connection) !Frame {
        // Read the first 2 bytes (header)
        const bytes_read = try self.stream.read(self.buffer[0..2]);
        if (bytes_read < 2) {
            return error.EndOfStream;
        }
        
        // Parse header
        const fin = (self.buffer[0] & 0x80) != 0;
        const rsv1 = (self.buffer[0] & 0x40) != 0;
        const rsv2 = (self.buffer[0] & 0x20) != 0;
        const rsv3 = (self.buffer[0] & 0x10) != 0;
        const opcode = @as(Opcode, @enumFromInt(self.buffer[0] & 0x0F));
        
        const mask = (self.buffer[1] & 0x80) != 0;
        var payload_length: u64 = @as(u64, @intCast(self.buffer[1] & 0x7F));
        
        // Read extended payload length if needed
        var header_size: usize = 2;
        if (payload_length == 126) {
            // 16-bit length
            _ = try self.stream.readAll(self.buffer[2..4]);
            payload_length = @as(u64, @intCast(self.buffer[2])) << 8 | @as(u64, @intCast(self.buffer[3]));
            header_size = 4;
        } else if (payload_length == 127) {
            // 64-bit length
            _ = try self.stream.readAll(self.buffer[2..10]);
            payload_length = @as(u64, @intCast(self.buffer[2])) << 56 |
                             @as(u64, @intCast(self.buffer[3])) << 48 |
                             @as(u64, @intCast(self.buffer[4])) << 40 |
                             @as(u64, @intCast(self.buffer[5])) << 32 |
                             @as(u64, @intCast(self.buffer[6])) << 24 |
                             @as(u64, @intCast(self.buffer[7])) << 16 |
                             @as(u64, @intCast(self.buffer[8])) << 8 |
                             @as(u64, @intCast(self.buffer[9]));
            header_size = 10;
        }
        
        // Read mask key if present
        var mask_key: ?[4]u8 = null;
        if (mask) {
            _ = try self.stream.readAll(self.buffer[header_size .. header_size + 4]);
            mask_key = [4]u8{
                self.buffer[header_size],
                self.buffer[header_size + 1],
                self.buffer[header_size + 2],
                self.buffer[header_size + 3],
            };
            header_size += 4;
        }
        
        // Read payload
        if (payload_length > self.buffer.len) {
            return error.PayloadTooLarge;
        }
        
        if (payload_length > 0) {
            _ = try self.stream.readAll(self.buffer[0..@intCast(payload_length)]);
        }
        
        // Copy payload
        var payload = try self.allocator.alloc(u8, @intCast(payload_length));
        @memcpy(payload, self.buffer[0..@intCast(payload_length)]);
        
        // Unmask payload if needed
        if (mask and mask_key != null) {
            unmaskPayload(payload, mask_key.?);
        }
        
        return Frame{
            .fin = fin,
            .rsv1 = rsv1,
            .rsv2 = rsv2,
            .rsv3 = rsv3,
            .opcode = opcode,
            .mask = mask,
            .payload_length = payload_length,
            .mask_key = mask_key,
            .payload = payload,
        };
    }
    
    /// Send a frame
    pub fn sendFrame(self: *Connection, frame: Frame) !void {
        // Calculate header size
        var header_size: usize = 2;
        if (frame.payload_length >= 126 and frame.payload_length <= 65535) {
            header_size = 4;
        } else if (frame.payload_length > 65535) {
            header_size = 10;
        }
        
        if (frame.mask) {
            header_size += 4;
        }
        
        // Encode header
        var header = try self.allocator.alloc(u8, header_size);
        defer self.allocator.free(header);
        
        // First byte: FIN, RSV1-3, opcode
        header[0] = @intCast((@intFromBool(frame.fin) << 7) |
                   (@intFromBool(frame.rsv1) << 6) |
                   (@intFromBool(frame.rsv2) << 5) |
                   (@intFromBool(frame.rsv3) << 4) |
                   @intFromEnum(frame.opcode));
        
        // Second byte: MASK, payload length
        if (frame.payload_length < 126) {
            header[1] = @intCast((@intFromBool(frame.mask) << 7) | @as(u7, @intCast(frame.payload_length)));
        } else if (frame.payload_length <= 65535) {
            header[1] = @intCast((@intFromBool(frame.mask) << 7) | 126);
            header[2] = @intCast((frame.payload_length >> 8) & 0xFF);
            header[3] = @intCast(frame.payload_length & 0xFF);
        } else {
            header[1] = @intCast((@intFromBool(frame.mask) << 7) | 127);
            header[2] = @intCast((frame.payload_length >> 56) & 0xFF);
            header[3] = @intCast((frame.payload_length >> 48) & 0xFF);
            header[4] = @intCast((frame.payload_length >> 40) & 0xFF);
            header[5] = @intCast((frame.payload_length >> 32) & 0xFF);
            header[6] = @intCast((frame.payload_length >> 24) & 0xFF);
            header[7] = @intCast((frame.payload_length >> 16) & 0xFF);
            header[8] = @intCast((frame.payload_length >> 8) & 0xFF);
            header[9] = @intCast(frame.payload_length & 0xFF);
        }
        
        // Add mask key if present
        if (frame.mask and frame.mask_key != null) {
            const mask_offset = header_size - 4;
            header[mask_offset] = frame.mask_key.?[0];
            header[mask_offset + 1] = frame.mask_key.?[1];
            header[mask_offset + 2] = frame.mask_key.?[2];
            header[mask_offset + 3] = frame.mask_key.?[3];
        }
        
        // Send header
        _ = try self.stream.write(header);
        
        // Send payload
        if (frame.payload_length > 0) {
            if (frame.mask and frame.mask_key != null) {
                // Create a masked copy of the payload
                var masked_payload = try self.allocator.alloc(u8, frame.payload.len);
                defer self.allocator.free(masked_payload);
                
                @memcpy(masked_payload, frame.payload);
                maskPayload(masked_payload, frame.mask_key.?);
                
                _ = try self.stream.write(masked_payload);
            } else {
                _ = try self.stream.write(frame.payload);
            }
        }
    }
    
    /// Send a text message
    pub fn sendText(self: *Connection, text: []const u8) !void {
        try self.sendFrame(Frame{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .text,
            .mask = false,
            .payload_length = text.len,
            .mask_key = null,
            .payload = text,
        });
    }
    
    /// Send a binary message
    pub fn sendBinary(self: *Connection, data: []const u8) !void {
        try self.sendFrame(Frame{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .binary,
            .mask = false,
            .payload_length = data.len,
            .mask_key = null,
            .payload = data,
        });
    }
    
    /// Send a ping message
    pub fn sendPing(self: *Connection, data: []const u8) !void {
        try self.sendFrame(Frame{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .ping,
            .mask = false,
            .payload_length = data.len,
            .mask_key = null,
            .payload = data,
        });
    }
    
    /// Send a pong message
    pub fn sendPong(self: *Connection, data: []const u8) !void {
        try self.sendFrame(Frame{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .pong,
            .mask = false,
            .payload_length = data.len,
            .mask_key = null,
            .payload = data,
        });
    }
    
    /// Send a close message
    pub fn sendClose(self: *Connection, code: u16, reason: []const u8) !void {
        var payload = try self.allocator.alloc(u8, 2 + reason.len);
        defer self.allocator.free(payload);
        
        payload[0] = @intCast((code >> 8) & 0xFF);
        payload[1] = @intCast(code & 0xFF);
        @memcpy(payload[2..], reason);
        
        try self.sendFrame(Frame{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .close,
            .mask = false,
            .payload_length = payload.len,
            .mask_key = null,
            .payload = payload,
        });
    }
};

/// Apply XOR mask to payload
fn maskPayload(payload: []u8, mask_key: [4]u8) void {
    for (payload, 0..) |*byte, i| {
        byte.* ^= mask_key[i % 4];
    }
}

/// Remove XOR mask from payload
fn unmaskPayload(payload: []u8, mask_key: [4]u8) void {
    // XOR is symmetric, so we can use the same function
    maskPayload(payload, mask_key);
}
