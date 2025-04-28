# websocket.zig Documentation

## Overview

The `websocket.zig` file implements WebSocket protocol handling for ZProxy. It provides structures and functions for processing WebSocket frames, managing connections, and handling messages.

## Key Components

### Opcode Enumeration

```zig
pub const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,
};
```

This enumeration defines the WebSocket frame opcodes:
- `continuation`: Continuation frame
- `text`: Text frame
- `binary`: Binary frame
- `close`: Connection close frame
- `ping`: Ping frame
- `pong`: Pong frame

### Frame Header

```zig
pub const FrameHeader = struct {
    fin: bool,
    rsv1: bool,
    rsv2: bool,
    rsv3: bool,
    opcode: Opcode,
    mask: bool,
    payload_length: u64,
    mask_key: ?[4]u8,
    
    pub fn parse(buffer: []const u8) !struct { header: FrameHeader, bytes_read: usize } {
        // Parse a frame header from a buffer
    }
    
    pub fn write(self: FrameHeader, buffer: []u8) !usize {
        // Write a frame header to a buffer
    }
};
```

This structure represents a WebSocket frame header:
- `fin`: Whether this is the final fragment in a message
- `rsv1`, `rsv2`, `rsv3`: Reserved bits
- `opcode`: The frame type
- `mask`: Whether the payload is masked
- `payload_length`: The length of the payload
- `mask_key`: The masking key (if masked)

The `parse` method parses a frame header from a buffer, and the `write` method writes a frame header to a buffer.

### WebSocket Connection

```zig
pub const WebSocketConnection = struct {
    stream: std.net.Stream,
    client_addr: std.net.Address,
    
    pub fn init(stream: std.net.Stream, client_addr: std.net.Address) WebSocketConnection {
        // Initialize a new WebSocket connection
    }
    
    pub fn handle(self: *WebSocketConnection, allocator: std.mem.Allocator, request: http1.Http1Request) !void {
        // Handle the connection
    }
    
    // Private methods for connection handling
    fn verifyUpgradeRequest(self: *WebSocketConnection, request: http1.Http1Request) bool { /* ... */ }
    fn sendUpgradeResponse(self: *WebSocketConnection) !void { /* ... */ }
    fn unmaskPayload(self: *WebSocketConnection, payload: []u8, mask_key: [4]u8) void { /* ... */ }
    fn processFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processTextFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processBinaryFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processPingFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processPongFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processCloseFrame(self: *WebSocketConnection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    
    // Public methods for sending messages
    pub fn sendTextMessage(self: *WebSocketConnection, message: []const u8) !void { /* ... */ }
    pub fn sendBinaryMessage(self: *WebSocketConnection, message: []const u8) !void { /* ... */ }
    pub fn sendPing(self: *WebSocketConnection, payload: []const u8) !void { /* ... */ }
    pub fn sendPong(self: *WebSocketConnection, payload: []const u8) !void { /* ... */ }
    pub fn sendClose(self: *WebSocketConnection, code: u16, reason: []const u8) !void { /* ... */ }
};
```

This structure represents a WebSocket connection:
- `stream`: The network stream
- `client_addr`: The client's address

The `init` method creates a new connection, and the `handle` method processes the connection.

The private methods handle specific aspects of the WebSocket protocol:
- `verifyUpgradeRequest`: Verifies that an HTTP request is a valid WebSocket upgrade request
- `sendUpgradeResponse`: Sends a WebSocket upgrade response
- `unmaskPayload`: Unmasks a payload using a masking key
- `processFrame`: Processes a frame based on its opcode
- `processTextFrame`, `processBinaryFrame`, etc.: Process specific frame types

The public methods send different types of messages:
- `sendTextMessage`: Sends a text message
- `sendBinaryMessage`: Sends a binary message
- `sendPing`: Sends a ping
- `sendPong`: Sends a pong
- `sendClose`: Sends a close frame

### Connection Handling

```zig
pub fn handleConnection(allocator: std.mem.Allocator, stream: std.net.Stream, client_addr: std.net.Address, request: http1.Http1Request) !void {
    // Handle a WebSocket connection
}
```

This function creates a WebSocket connection and handles it.

### Testing

```zig
test "WebSocket - Frame Header" {
    // Test frame header parsing and writing
}
```

This test ensures that frame header parsing and writing work correctly.

## WebSocket Protocol Flow

1. **Handshake**: The client sends an HTTP upgrade request, and the server responds with an HTTP 101 Switching Protocols response.
2. **Data Transfer**: Both endpoints can send frames (text, binary, ping, pong, close).
3. **Closing**: Either endpoint can initiate closing by sending a close frame, which the other endpoint should respond to with a close frame.

## Zig Programming Principles

1. **Binary Protocol Handling**: The code carefully handles binary data, parsing and generating WebSocket frames.
2. **Error Handling**: Functions that can fail return errors using Zig's error union type.
3. **Testing**: Tests are integrated directly into the code.
4. **Resource Safety**: The code uses proper error handling to ensure resources are properly managed.
5. **Bit Manipulation**: The code uses bit manipulation to handle WebSocket's binary format.

## Usage Example

```zig
// Handle a WebSocket connection
try websocket.handleConnection(allocator, stream, client_addr, request);

// In a WebSocket connection
var connection = websocket.WebSocketConnection.init(stream, client_addr);

// Send a text message
try connection.sendTextMessage("Hello, WebSocket!");

// Send a binary message
try connection.sendBinaryMessage(&[_]u8{ 0x01, 0x02, 0x03 });

// Send a ping
try connection.sendPing("ping");

// Close the connection
try connection.sendClose(1000, "Normal closure");
```

## Limitations

This implementation is simplified and does not include:
- Message fragmentation
- Extensions
- Subprotocols
- Proper Sec-WebSocket-Accept calculation
- Full error handling

A production-ready implementation would need to address these aspects of the WebSocket protocol.
