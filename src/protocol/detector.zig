const std = @import("std");
const logger = @import("../utils/logger.zig");

/// Protocol types that can be detected
pub const DetectedProtocol = enum {
    http1,
    http2,
    websocket,
    unknown,
};

/// Detect the protocol from a stream
pub fn detectProtocol(stream: std.net.Stream) !DetectedProtocol {
    // Read the first few bytes to detect the protocol
    var buffer: [24]u8 = undefined;
    const bytes_read = try stream.peek(&buffer);
    
    if (bytes_read == 0) {
        logger.debug("Empty connection", .{});
        return .unknown;
    }
    
    // Check for HTTP/2 preface
    if (bytes_read >= 24 and std.mem.eql(u8, buffer[0..24], "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")) {
        logger.debug("Detected HTTP/2 preface", .{});
        return .http2;
    }
    
    // Check for HTTP/1.x methods
    const http_methods = [_][]const u8{
        "GET ",
        "POST ",
        "PUT ",
        "DELETE ",
        "HEAD ",
        "OPTIONS ",
        "PATCH ",
        "CONNECT ",
        "TRACE ",
    };
    
    for (http_methods) |method| {
        if (bytes_read >= method.len and std.mem.eql(u8, buffer[0..method.len], method)) {
            logger.debug("Detected HTTP/1.1 method: {s}", .{method});
            return .http1;
        }
    }
    
    // Check for WebSocket upgrade request
    if (isWebSocketUpgrade(buffer[0..bytes_read])) {
        logger.debug("Detected WebSocket upgrade request", .{});
        return .websocket;
    }
    
    // Unknown protocol
    logger.debug("Unknown protocol: {s}", .{buffer[0..@min(bytes_read, 16)]});
    return .unknown;
}

/// Check if a buffer contains a WebSocket upgrade request
fn isWebSocketUpgrade(buffer: []const u8) bool {
    // WebSocket upgrade requests are HTTP/1.1 requests with specific headers
    // This is a simplified check that looks for "Upgrade: websocket"
    return std.mem.indexOf(u8, buffer, "Upgrade: websocket") != null or
           std.mem.indexOf(u8, buffer, "Upgrade: WebSocket") != null;
}

test "Protocol Detection - HTTP/1.1" {
    const testing = std.testing;
    
    // Create a pipe for testing
    var pipe = try std.os.pipe();
    defer std.os.close(pipe[0]);
    defer std.os.close(pipe[1]);
    
    // Create a stream from the pipe
    var stream = std.net.Stream{ .handle = pipe[0] };
    
    // Write an HTTP/1.1 request to the pipe
    const request = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n";
    _ = try std.os.write(pipe[1], request);
    
    // Detect the protocol
    const detected = try detectProtocol(stream);
    
    // Check that HTTP/1.1 was detected
    try testing.expectEqual(DetectedProtocol.http1, detected);
}

test "Protocol Detection - HTTP/2" {
    const testing = std.testing;
    
    // Create a pipe for testing
    var pipe = try std.os.pipe();
    defer std.os.close(pipe[0]);
    defer std.os.close(pipe[1]);
    
    // Create a stream from the pipe
    var stream = std.net.Stream{ .handle = pipe[0] };
    
    // Write an HTTP/2 preface to the pipe
    const preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
    _ = try std.os.write(pipe[1], preface);
    
    // Detect the protocol
    const detected = try detectProtocol(stream);
    
    // Check that HTTP/2 was detected
    try testing.expectEqual(DetectedProtocol.http2, detected);
}

test "Protocol Detection - WebSocket" {
    const testing = std.testing;
    
    // Create a pipe for testing
    var pipe = try std.os.pipe();
    defer std.os.close(pipe[0]);
    defer std.os.close(pipe[1]);
    
    // Create a stream from the pipe
    var stream = std.net.Stream{ .handle = pipe[0] };
    
    // Write a WebSocket upgrade request to the pipe
    const request = "GET / HTTP/1.1\r\nHost: example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n";
    _ = try std.os.write(pipe[1], request);
    
    // Detect the protocol
    const detected = try detectProtocol(stream);
    
    // Check that WebSocket was detected
    try testing.expectEqual(DetectedProtocol.websocket, detected);
}

test "Protocol Detection - Unknown" {
    const testing = std.testing;
    
    // Create a pipe for testing
    var pipe = try std.os.pipe();
    defer std.os.close(pipe[0]);
    defer std.os.close(pipe[1]);
    
    // Create a stream from the pipe
    var stream = std.net.Stream{ .handle = pipe[0] };
    
    // Write some random data to the pipe
    const data = "This is not a valid HTTP request";
    _ = try std.os.write(pipe[1], data);
    
    // Detect the protocol
    const detected = try detectProtocol(stream);
    
    // Check that the protocol is unknown
    try testing.expectEqual(DetectedProtocol.unknown, detected);
}
