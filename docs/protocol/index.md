# ZProxy Protocol Handlers

This document describes the protocol handlers in ZProxy.

## Overview

ZProxy supports multiple protocols:

1. **HTTP/1.1**: Standard HTTP protocol with support for all HTTP methods.
2. **HTTP/2**: Modern HTTP protocol with multiplexing and header compression.
3. **WebSocket**: Protocol for bidirectional communication over a single TCP connection.

The protocol detector examines the initial bytes of a connection to determine which protocol is being used, then hands off the connection to the appropriate handler.

## Protocol Detection

The protocol detector is implemented in `src/protocol/detector.zig`. It examines the initial bytes of a connection to determine which protocol is being used.

### Detection Algorithm

1. Read the first bytes of the connection
2. Check for HTTP/2 preface (`PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`)
3. Check for HTTP/1.1 methods (GET, POST, PUT, etc.)
4. Check for WebSocket upgrade header
5. If none of the above, return unknown protocol

```zig
pub fn detectProtocol(stream: std.net.Stream) !Protocol {
    // Read the first bytes of the connection
    var buffer: [24]u8 = undefined;
    const bytes_read = try stream.read(&buffer);
    
    if (bytes_read == 0) {
        return error.EmptyStream;
    }
    
    // Check for HTTP/2 preface
    if (bytes_read >= 24 and std.mem.eql(u8, buffer[0..24], "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")) {
        logger.debug("Detected HTTP/2 protocol", .{});
        return .http2;
    }
    
    // Check for HTTP/1.x
    if (bytes_read >= 4 and (std.mem.eql(u8, buffer[0..4], "GET ") or
                             std.mem.eql(u8, buffer[0..4], "POST") or
                             std.mem.eql(u8, buffer[0..4], "PUT ") or
                             std.mem.eql(u8, buffer[0..4], "HEAD") or
                             std.mem.eql(u8, buffer[0..4], "DELE") or
                             std.mem.eql(u8, buffer[0..4], "PATC") or
                             std.mem.eql(u8, buffer[0..4], "OPTI")))
    {
        // Check for WebSocket upgrade
        if (isWebSocketUpgrade(buffer[0..bytes_read])) {
            logger.debug("Detected WebSocket protocol", .{});
            return .websocket;
        }
        
        logger.debug("Detected HTTP/1.x protocol", .{});
        return .http1;
    }
    
    logger.warning("Unknown protocol", .{});
    return .unknown;
}
```

## HTTP/1.1

The HTTP/1.1 protocol handler is implemented in `src/protocol/http1.zig`. It handles HTTP/1.1 requests and responses.

### Features

- Support for all HTTP methods (GET, POST, PUT, DELETE, etc.)
- Support for request and response headers
- Support for request and response bodies
- Support for chunked transfer encoding
- Support for keep-alive connections

### Request Parsing

The HTTP/1.1 protocol handler parses requests using the following steps:

1. Parse the request line (method, path, version)
2. Parse the headers
3. Parse the body (if present)

### Response Generation

The HTTP/1.1 protocol handler generates responses using the following steps:

1. Generate the status line (version, status code, status text)
2. Generate the headers
3. Generate the body (if present)

## HTTP/2

The HTTP/2 protocol handler is implemented in `src/protocol/http2.zig`. It handles HTTP/2 requests and responses.

### Features

- Support for multiplexing (multiple requests over a single connection)
- Support for header compression
- Support for server push
- Support for stream prioritization
- Support for flow control

### Frame Types

HTTP/2 uses a binary framing layer. The following frame types are supported:

- DATA: Used to transport HTTP message bodies
- HEADERS: Used to communicate header fields
- PRIORITY: Used to signal the priority of a stream
- RST_STREAM: Used to terminate a stream
- SETTINGS: Used to communicate configuration parameters
- PUSH_PROMISE: Used to notify the peer of a stream the sender intends to initiate
- PING: Used to measure round-trip time and check connection liveness
- GOAWAY: Used to initiate connection shutdown
- WINDOW_UPDATE: Used to implement flow control
- CONTINUATION: Used to continue a sequence of header block fragments

### Stream States

HTTP/2 streams can be in the following states:

- idle: Initial state
- reserved (local): Endpoint has sent a PUSH_PROMISE frame
- reserved (remote): Endpoint has received a PUSH_PROMISE frame
- open: Endpoint can send frames
- half-closed (local): Endpoint has sent an END_STREAM flag
- half-closed (remote): Endpoint has received an END_STREAM flag
- closed: Stream is terminated

## WebSocket

The WebSocket protocol handler is implemented in `src/protocol/websocket.zig`. It handles WebSocket connections.

### Features

- Support for text and binary messages
- Support for ping/pong for connection liveness
- Support for close frames for connection termination
- Support for fragmented messages

### Frame Types

WebSocket uses a framing protocol. The following frame types are supported:

- Continuation: Used to continue a fragmented message
- Text: Used to send text data
- Binary: Used to send binary data
- Close: Used to close the connection
- Ping: Used to check connection liveness
- Pong: Used to respond to ping frames

### Handshake

WebSocket connections start with an HTTP/1.1 handshake. The client sends an HTTP/1.1 request with the following headers:

- `Upgrade: websocket`
- `Connection: Upgrade`
- `Sec-WebSocket-Key: <base64-encoded-value>`
- `Sec-WebSocket-Version: 13`

The server responds with an HTTP/1.1 101 Switching Protocols response with the following headers:

- `Upgrade: websocket`
- `Connection: Upgrade`
- `Sec-WebSocket-Accept: <base64-encoded-value>`

After the handshake, the connection is upgraded to the WebSocket protocol.

## Protocol Configuration

The protocols can be configured in the configuration file:

```json
{
  "protocols": ["http1", "http2", "websocket"]
}
```

This enables all three protocols. To disable a protocol, remove it from the array.

## Protocol Extensions

ZProxy is designed to be extensible. New protocols can be added by implementing a protocol handler and updating the protocol detector.

To add a new protocol:

1. Create a new file in the `src/protocol` directory
2. Implement the protocol handler
3. Update the protocol detector to detect the new protocol
4. Update the configuration to support the new protocol
