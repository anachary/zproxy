# server.zig Documentation

## Overview

The `server.zig` file implements the core server functionality for ZProxy. It handles connection acceptance, worker thread management, protocol detection, and request processing.

## Key Components

### Connection Structure

```zig
pub const Connection = struct {
    stream: std.net.Stream,
    client_addr: std.net.Address,
    server: *Server,
    
    pub fn handle(self: *Connection) !void {
        // Handle a connection
    }
    
    // Protocol-specific handlers
    fn handleHttp1(self: *Connection) !void { /* ... */ }
    fn handleHttp2(self: *Connection) !void { /* ... */ }
    fn handleWebsocket(self: *Connection) !void { /* ... */ }
    
    // Response helpers
    fn sendOk(self: *Connection) !void { /* ... */ }
    fn sendNotFound(self: *Connection) !void { /* ... */ }
    fn sendForbidden(self: *Connection, reason: []const u8) !void { /* ... */ }
    fn sendNotImplemented(self: *Connection) !void { /* ... */ }
};
```

This structure represents a client connection:
- `stream`: The network stream for reading and writing data
- `client_addr`: The client's address
- `server`: A pointer to the server instance

The `handle` method is the main entry point for processing a connection:
1. Sets connection timeouts
2. Detects the protocol (HTTP/1.1, HTTP/2, WebSocket)
3. Calls the appropriate protocol-specific handler

Protocol-specific handlers:
- `handleHttp1`: Processes HTTP/1.1 requests
- `handleHttp2`: Processes HTTP/2 requests (not fully implemented)
- `handleWebsocket`: Processes WebSocket connections (not fully implemented)

Response helpers:
- `sendOk`: Sends a 200 OK response
- `sendNotFound`: Sends a 404 Not Found response
- `sendForbidden`: Sends a 403 Forbidden response
- `sendNotImplemented`: Sends a 501 Not Implemented response

### HTTP Request Parsing

```zig
const Http1Request = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
};

fn parseHttp1Request(buffer: []const u8) !Http1Request {
    // Parse HTTP/1.1 request
}
```

This section handles HTTP/1.1 request parsing:
- `Http1Request`: A structure representing an HTTP/1.1 request
- `parseHttp1Request`: A function that parses a raw HTTP request into an `Http1Request` structure

### Worker Thread Management

```zig
const WorkerContext = struct {
    server: *Server,
    thread_id: usize,
};

fn workerThread(context: *WorkerContext) !void {
    // Worker thread function
}
```

This section handles worker thread management:
- `WorkerContext`: A structure containing context for a worker thread
- `workerThread`: The main function for worker threads

The worker thread function:
1. Waits for a connection from the connection queue
2. Processes the connection
3. Repeats until shutdown is requested

### Server Structure

```zig
pub const Server = struct {
    allocator: std.mem.Allocator,
    config: config.Config,
    stream_server: std.net.StreamServer,
    router: router.Router,
    middleware: middleware.MiddlewareChain,
    
    // Thread management
    worker_threads: []std.Thread,
    worker_contexts: []WorkerContext,
    
    // Connection queue
    connection_queue: std.fifo.LinearFifo(std.net.StreamServer.Connection, .Dynamic),
    queue_mutex: std.Thread.Mutex,
    connection_semaphore: std.Thread.Semaphore,
    
    // Shutdown flag
    shutdown_requested: std.atomic.Atomic(bool),
    
    pub fn init(allocator: std.mem.Allocator, server_config: config.Config) !Server {
        // Initialize the server
    }
    
    pub fn start(self: *Server) !void {
        // Start the server
    }
    
    pub fn stop(self: *Server) !void {
        // Stop the server
    }
    
    pub fn deinit(self: *Server) void {
        // Clean up server resources
    }
};
```

This is the main server structure:
- `allocator`: Memory allocator
- `config`: Server configuration
- `stream_server`: Zig's stream server for accepting connections
- `router`: Router for matching requests to routes
- `middleware`: Middleware chain for processing requests
- Thread management fields for worker threads
- Connection queue fields for passing connections to worker threads
- `shutdown_requested`: Atomic flag for signaling shutdown

Key methods:
- `init`: Initializes the server with the given configuration
- `start`: Starts the server and begins accepting connections
- `stop`: Stops the server gracefully
- `deinit`: Cleans up server resources

The `start` method:
1. Binds to the configured address and port
2. Starts worker threads
3. Accepts connections in a loop
4. Adds connections to the queue for processing by worker threads

The `stop` method:
1. Sets the shutdown flag
2. Closes the server socket
3. Signals all worker threads to exit
4. Waits for all worker threads to exit

### Testing

```zig
test "Server - Initialization" {
    // Test server initialization
}
```

This test ensures that the server initializes correctly with a given configuration.

## Zig Programming Principles

1. **Concurrency**: The server uses a thread pool model with a connection queue for efficient handling of concurrent connections.
2. **Thread Safety**: Mutexes and atomic variables are used to ensure thread safety.
3. **Error Handling**: Functions that can fail return errors using Zig's error union type.
4. **Resource Management**: The code carefully manages resources, allocating memory and creating threads as needed and providing `deinit` methods to clean up.
5. **Testing**: Tests are integrated directly into the code.

## Usage Example

```zig
// Create a server configuration
var server_config = config.getDefaultConfig(allocator);
defer server_config.deinit();

// Initialize the server
var proxy_server = try server.Server.init(allocator, server_config);
defer proxy_server.deinit();

// Start the server (this blocks until the server is stopped)
try proxy_server.start();

// Stop the server gracefully
try proxy_server.stop();
```
