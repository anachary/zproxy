# detector.zig Documentation

## Overview

The `detector.zig` file implements protocol detection for ZProxy. It examines the initial bytes of a connection to determine which protocol is being used (HTTP/1.1, HTTP/2, or WebSocket).

## Key Components

### Protocol Enumeration

```zig
pub const DetectedProtocol = enum {
    http1,
    http2,
    websocket,
    unknown,
};
```

This enumeration defines the protocols that can be detected:
- `http1`: HTTP/1.1 protocol
- `http2`: HTTP/2 protocol
- `websocket`: WebSocket protocol
- `unknown`: Unknown or unsupported protocol

### Protocol Detection

```zig
pub fn detectProtocol(stream: std.net.Stream) !DetectedProtocol {
    // Detect the protocol from a stream
}
```

This is the main function for protocol detection. It:
1. Peeks at the first few bytes of the stream without consuming them
2. Checks for protocol-specific patterns
3. Returns the detected protocol

The detection process:
1. Check for the HTTP/2 preface (`PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`)
2. Check for HTTP/1.x methods (GET, POST, etc.)
3. Check for WebSocket upgrade requests
4. If none of the above match, return `unknown`

### WebSocket Detection

```zig
fn isWebSocketUpgrade(buffer: []const u8) bool {
    // Check if a buffer contains a WebSocket upgrade request
}
```

This helper function checks if a buffer contains a WebSocket upgrade request by looking for the `Upgrade: websocket` header.

### Testing

```zig
test "Protocol Detection - HTTP/1.1" {
    // Test HTTP/1.1 detection
}

test "Protocol Detection - HTTP/2" {
    // Test HTTP/2 detection
}

test "Protocol Detection - WebSocket" {
    // Test WebSocket detection
}

test "Protocol Detection - Unknown" {
    // Test unknown protocol detection
}
```

These tests ensure that the protocol detection works correctly for different protocols:
1. Create a pipe for testing
2. Write protocol-specific data to one end of the pipe
3. Create a stream from the other end of the pipe
4. Call `detectProtocol` on the stream
5. Check that the correct protocol is detected

## Zig Programming Principles

1. **Non-blocking I/O**: The `peek` function is used to examine data without consuming it, allowing the actual protocol handler to read the data later.
2. **Error Handling**: Functions that can fail return errors using Zig's error union type.
3. **Testing**: Tests are integrated directly into the code, with each test case checking a specific protocol.
4. **Resource Management**: The tests properly clean up resources using `defer` statements.

## Usage Example

```zig
// Create a connection
var connection = Connection{
    .stream = stream,
    .client_addr = client_addr,
    .server = server,
};

// Detect the protocol
const detected_protocol = try protocol.detectProtocol(connection.stream);

// Handle the protocol
switch (detected_protocol) {
    .http1 => try connection.handleHttp1(),
    .http2 => try connection.handleHttp2(),
    .websocket => try connection.handleWebsocket(),
    .unknown => {
        logger.warning("Unknown protocol", .{});
        return error.UnknownProtocol;
    },
}
```
