const std = @import("std");

// Import protocol handlers
pub const http1 = @import("http1/handler.zig");
pub const http2 = @import("http2/handler.zig");
pub const websocket = @import("websocket/handler.zig");

/// Supported protocols
pub const Protocol = enum {
    http1,
    http2,
    websocket,
    unknown,
};

/// Detect the protocol from the initial bytes of a connection
pub fn detectProtocol(conn_context: anytype) !Protocol {
    const logger = std.log.scoped(.protocol_detector);
    
    // Read initial bytes from the connection
    const bytes_read = try conn_context.connection.stream.read(conn_context.buffer);
    if (bytes_read == 0) {
        logger.debug("Connection closed before protocol detection", .{});
        return Protocol.unknown;
    }
    
    // Check for HTTP/2 preface
    if (bytes_read >= 24 and std.mem.eql(u8, conn_context.buffer[0..24], "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")) {
        logger.debug("Detected HTTP/2 protocol", .{});
        return Protocol.http2;
    }
    
    // Check for HTTP/1.x
    if (bytes_read >= 4 and (
        std.mem.eql(u8, conn_context.buffer[0..4], "GET ") or
        std.mem.eql(u8, conn_context.buffer[0..4], "POST") or
        std.mem.eql(u8, conn_context.buffer[0..4], "PUT ") or
        std.mem.eql(u8, conn_context.buffer[0..4], "DELE") or
        std.mem.eql(u8, conn_context.buffer[0..4], "HEAD") or
        std.mem.eql(u8, conn_context.buffer[0..4], "OPTI") or
        std.mem.eql(u8, conn_context.buffer[0..4], "PATC") or
        std.mem.eql(u8, conn_context.buffer[0..4], "TRAC")
    )) {
        // Check for WebSocket upgrade
        if (isWebSocketUpgrade(conn_context.buffer[0..bytes_read])) {
            logger.debug("Detected WebSocket protocol", .{});
            return Protocol.websocket;
        }
        
        logger.debug("Detected HTTP/1.x protocol", .{});
        return Protocol.http1;
    }
    
    logger.warn("Unknown protocol", .{});
    return Protocol.unknown;
}

/// Check if the HTTP request is a WebSocket upgrade
fn isWebSocketUpgrade(buffer: []const u8) bool {
    // Look for "Upgrade: websocket" and "Connection: Upgrade" headers
    return std.mem.indexOf(u8, buffer, "Upgrade: websocket") != null and
           std.mem.indexOf(u8, buffer, "Connection: Upgrade") != null;
}

// Tests
test "Protocol detection - HTTP/1.1" {
    const testing = std.testing;
    
    // Mock connection context
    var buffer: [1024]u8 = undefined;
    _ = std.mem.copy(u8, &buffer, "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n");
    
    var mock_context = MockConnectionContext{
        .buffer = &buffer,
        .bytes_read = 40,
    };
    
    const protocol = try mockDetectProtocol(&mock_context);
    try testing.expectEqual(Protocol.http1, protocol);
}

test "Protocol detection - HTTP/2" {
    const testing = std.testing;
    
    // Mock connection context
    var buffer: [1024]u8 = undefined;
    _ = std.mem.copy(u8, &buffer, "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\nSome data");
    
    var mock_context = MockConnectionContext{
        .buffer = &buffer,
        .bytes_read = 30,
    };
    
    const protocol = try mockDetectProtocol(&mock_context);
    try testing.expectEqual(Protocol.http2, protocol);
}

test "Protocol detection - WebSocket" {
    const testing = std.testing;
    
    // Mock connection context
    var buffer: [1024]u8 = undefined;
    _ = std.mem.copy(
        u8,
        &buffer,
        "GET / HTTP/1.1\r\nHost: example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"
    );
    
    var mock_context = MockConnectionContext{
        .buffer = &buffer,
        .bytes_read = 80,
    };
    
    const protocol = try mockDetectProtocol(&mock_context);
    try testing.expectEqual(Protocol.websocket, protocol);
}

// Mock types for testing
const MockConnectionContext = struct {
    buffer: []u8,
    bytes_read: usize,
};

fn mockDetectProtocol(mock_context: *MockConnectionContext) !Protocol {
    if (mock_context.bytes_read >= 24 and 
        std.mem.eql(u8, mock_context.buffer[0..24], "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")) {
        return Protocol.http2;
    }
    
    if (mock_context.bytes_read >= 4 and (
        std.mem.eql(u8, mock_context.buffer[0..4], "GET ") or
        std.mem.eql(u8, mock_context.buffer[0..4], "POST") or
        std.mem.eql(u8, mock_context.buffer[0..4], "PUT ") or
        std.mem.eql(u8, mock_context.buffer[0..4], "DELE") or
        std.mem.eql(u8, mock_context.buffer[0..4], "HEAD") or
        std.mem.eql(u8, mock_context.buffer[0..4], "OPTI") or
        std.mem.eql(u8, mock_context.buffer[0..4], "PATC") or
        std.mem.eql(u8, mock_context.buffer[0..4], "TRAC")
    )) {
        if (isWebSocketUpgrade(mock_context.buffer[0..mock_context.bytes_read])) {
            return Protocol.websocket;
        }
        
        return Protocol.http1;
    }
    
    return Protocol.unknown;
}
