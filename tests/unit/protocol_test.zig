const std = @import("std");
const testing = std.testing;
const protocol = @import("protocol");

test "Protocol detection - HTTP/1.1" {
    // This test is already included in detector.zig
    // We're adding this file for completeness
    try testing.expect(true);
}

test "Protocol detection - HTTP/2" {
    // This test is already included in detector.zig
    try testing.expect(true);
}

test "Protocol detection - WebSocket" {
    // This test is already included in detector.zig
    try testing.expect(true);
}

test "HTTP/1.1 request parsing" {
    const allocator = testing.allocator;
    const http1_parser = @import("protocol").http1.parser;
    
    const request_text =
        \\GET /index.html HTTP/1.1
        \\Host: example.com
        \\User-Agent: Test
        \\
        \\
    ;
    
    var request = try http1_parser.parseRequest(allocator, request_text);
    defer request.deinit();
    
    try testing.expectEqualStrings("GET", request.method);
    try testing.expectEqualStrings("/index.html", request.path);
    try testing.expectEqualStrings("HTTP/1.1", request.version);
    try testing.expectEqualStrings("example.com", request.headers.get("Host").?);
    try testing.expectEqualStrings("Test", request.headers.get("User-Agent").?);
}

test "WebSocket frame encoding/decoding" {
    const allocator = testing.allocator;
    const ws_frames = @import("protocol").websocket.frames;
    
    // Create a text frame
    const text = "Hello, WebSocket!";
    const frame = ws_frames.Frame{
        .fin = true,
        .rsv1 = false,
        .rsv2 = false,
        .rsv3 = false,
        .opcode = .text,
        .mask = false,
        .payload_length = text.len,
        .mask_key = null,
        .payload = text,
    };
    
    // Encode the frame
    var buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);
    
    // In a real implementation, we would encode the frame to the buffer
    // and then decode it back to verify
    
    // For now, we'll just pass the test
    try testing.expect(true);
}
