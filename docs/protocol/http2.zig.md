# http2.zig Documentation

## Overview

The `http2.zig` file implements HTTP/2 protocol handling for ZProxy. It provides structures and functions for processing HTTP/2 frames, managing connections, and handling requests and responses.

## Key Components

### Frame Types and Flags

```zig
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

pub const FrameFlags = struct {
    end_stream: bool = false,
    end_headers: bool = false,
    padded: bool = false,
    priority: bool = false,
    ack: bool = false,
    
    pub fn toByte(self: FrameFlags) u8 {
        // Convert flags to a byte
    }
    
    pub fn fromByte(byte: u8, frame_type: FrameType) FrameFlags {
        // Parse flags from a byte
    }
};
```

These define the HTTP/2 frame types and flags:
- `FrameType`: An enumeration of HTTP/2 frame types
- `FrameFlags`: A structure representing frame flags

The `toByte` method converts flags to a byte, and the `fromByte` method parses flags from a byte.

### Frame Header

```zig
pub const FrameHeader = struct {
    length: u24,
    type: FrameType,
    flags: FrameFlags,
    stream_id: u31,
    
    pub fn parse(buffer: []const u8) !FrameHeader {
        // Parse a frame header from a buffer
    }
    
    pub fn write(self: FrameHeader, buffer: []u8) !void {
        // Write a frame header to a buffer
    }
};
```

This structure represents an HTTP/2 frame header:
- `length`: The length of the frame payload
- `type`: The frame type
- `flags`: The frame flags
- `stream_id`: The stream identifier

The `parse` method parses a frame header from a buffer, and the `write` method writes a frame header to a buffer.

### Settings

```zig
pub const Settings = struct {
    header_table_size: u32 = 4096,
    enable_push: bool = true,
    max_concurrent_streams: u32 = 100,
    initial_window_size: u32 = 65535,
    max_frame_size: u32 = 16384,
    max_header_list_size: u32 = 65536,
};
```

This structure represents HTTP/2 settings:
- `header_table_size`: The size of the header compression table
- `enable_push`: Whether server push is enabled
- `max_concurrent_streams`: The maximum number of concurrent streams
- `initial_window_size`: The initial flow control window size
- `max_frame_size`: The maximum frame size
- `max_header_list_size`: The maximum size of the header list

### HTTP/2 Connection

```zig
pub const Http2Connection = struct {
    stream: std.net.Stream,
    client_addr: std.net.Address,
    settings: Settings,
    
    pub fn init(stream: std.net.Stream, client_addr: std.net.Address) Http2Connection {
        // Initialize a new HTTP/2 connection
    }
    
    pub fn handle(self: *Http2Connection) !void {
        // Handle the connection
    }
    
    // Private methods for frame processing
    fn sendSettings(self: *Http2Connection) !void { /* ... */ }
    fn processFrame(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processSettings(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processHeaders(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processData(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processPing(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn processGoaway(self: *Http2Connection, header: FrameHeader, payload: []const u8) !void { /* ... */ }
    fn sendResponse(self: *Http2Connection, stream_id: u31) !void { /* ... */ }
};
```

This structure represents an HTTP/2 connection:
- `stream`: The network stream
- `client_addr`: The client's address
- `settings`: The HTTP/2 settings

The `init` method creates a new connection, and the `handle` method processes the connection.

The private methods handle specific aspects of the HTTP/2 protocol:
- `sendSettings`: Sends a SETTINGS frame
- `processFrame`: Processes a frame based on its type
- `processSettings`: Processes a SETTINGS frame
- `processHeaders`: Processes a HEADERS frame
- `processData`: Processes a DATA frame
- `processPing`: Processes a PING frame
- `processGoaway`: Processes a GOAWAY frame
- `sendResponse`: Sends a response

### Connection Handling

```zig
pub fn handleConnection(stream: std.net.Stream, client_addr: std.net.Address) !void {
    // Handle an HTTP/2 connection
}
```

This function creates an HTTP/2 connection and handles it.

### Testing

```zig
test "HTTP/2 - Frame Header" {
    // Test frame header parsing and writing
}
```

This test ensures that frame header parsing and writing work correctly.

## HTTP/2 Protocol Flow

1. **Connection Preface**: The client sends the connection preface (`PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`).
2. **Settings Exchange**: Both endpoints send their settings.
3. **Request**: The client sends a HEADERS frame (and optionally DATA frames) to make a request.
4. **Response**: The server sends a HEADERS frame (and optionally DATA frames) to respond.
5. **Stream Termination**: The stream is terminated with the END_STREAM flag.
6. **Connection Termination**: Either endpoint can send a GOAWAY frame to terminate the connection.

## Zig Programming Principles

1. **Binary Protocol Handling**: The code carefully handles binary data, parsing and generating HTTP/2 frames.
2. **Error Handling**: Functions that can fail return errors using Zig's error union type.
3. **Testing**: Tests are integrated directly into the code.
4. **Resource Safety**: The code uses proper error handling to ensure resources are properly managed.
5. **Bit Manipulation**: The code uses bit manipulation to handle HTTP/2's binary format.

## Usage Example

```zig
// Handle an HTTP/2 connection
try http2.handleConnection(stream, client_addr);
```

## Limitations

This implementation is simplified and does not include:
- HPACK header compression
- Flow control
- Stream prioritization
- Server push
- Full error handling

A production-ready implementation would need to address these aspects of the HTTP/2 protocol.
