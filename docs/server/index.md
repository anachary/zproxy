# ZProxy Server

This document describes the server component of ZProxy.

## Overview

The server component is responsible for accepting connections, managing the connection lifecycle, and dispatching requests to the appropriate handlers.

## Server Implementation

The server is implemented in `src/server/server.zig`. It provides the following functionality:

- Listening for incoming connections
- Accepting connections
- Creating a thread for each connection
- Managing the connection lifecycle
- Handling errors

### Server Configuration

The server is configured using the following options:

```json
{
  "host": "0.0.0.0",
  "port": 8000,
  "thread_count": 4,
  "backlog": 128,
  "max_connections": 1000,
  "connection_timeout_ms": 30000
}
```

- `host`: The host to listen on
- `port`: The port to listen on
- `thread_count`: The number of threads to use
- `backlog`: The maximum number of pending connections
- `max_connections`: The maximum number of concurrent connections
- `connection_timeout_ms`: The connection timeout in milliseconds

### Server Lifecycle

1. The server is initialized with the configuration
2. The server creates a listener socket
3. The server starts accepting connections
4. For each connection, the server creates a thread to handle it
5. The server continues accepting connections until it is stopped
6. When the server is stopped, it closes the listener socket and waits for all connection threads to finish

## Connection Handling

The connection handling is implemented in `src/server/connection.zig`. It provides the following functionality:

- Reading from the connection
- Writing to the connection
- Detecting the protocol
- Dispatching to the appropriate protocol handler
- Handling errors
- Closing the connection

### Connection Lifecycle

1. The connection is accepted by the server
2. The connection is passed to a connection handler
3. The connection handler detects the protocol
4. The connection handler dispatches to the appropriate protocol handler
5. The protocol handler processes the request
6. The protocol handler sends the response
7. The connection is closed (unless keep-alive is enabled)

## Thread Pool

The thread pool is implemented in `src/server/thread_pool.zig`. It provides the following functionality:

- Creating a pool of worker threads
- Assigning tasks to worker threads
- Managing the lifecycle of worker threads
- Handling errors

### Thread Pool Configuration

The thread pool is configured using the `thread_count` option in the server configuration.

### Thread Pool Lifecycle

1. The thread pool is initialized with the specified number of threads
2. Each thread in the pool waits for a task
3. When a task is assigned, the thread executes it
4. After executing the task, the thread waits for another task
5. When the thread pool is stopped, all threads are signaled to exit
6. The thread pool waits for all threads to exit

## NUMA Awareness

ZProxy is NUMA-aware, meaning it can optimize for multi-socket systems. This is implemented in `src/utils/numa.zig`.

### NUMA Configuration

NUMA awareness is enabled by default. It can be disabled by setting the `numa_aware` option to `false` in the server configuration.

### NUMA Optimization

When NUMA awareness is enabled, ZProxy:

1. Detects the NUMA topology of the system
2. Assigns threads to NUMA nodes
3. Allocates memory from the local NUMA node
4. Minimizes cross-node memory access

This optimization can significantly improve performance on multi-socket systems.

## Error Handling

The server component handles errors at different levels:

- **Socket Errors**: Errors related to socket operations (accept, read, write, close)
- **Protocol Errors**: Errors related to protocol handling
- **Thread Errors**: Errors related to thread creation and management
- **Memory Errors**: Errors related to memory allocation and deallocation

Errors are logged and, where possible, handled gracefully to prevent the server from crashing.

## Performance Considerations

The server component is designed for high performance:

- **Zero-Copy**: Minimizes memory copying for better performance
- **Buffer Pooling**: Reuses buffers to reduce memory allocations
- **Connection Pooling**: Maintains connections to upstream services
- **NUMA Awareness**: Optimizes for multi-socket systems
- **Thread-per-Connection**: Provides good performance for long-lived connections
- **Thread Pool**: Provides good scalability for a large number of connections

## Server API

The server component provides the following API:

### Server

```zig
pub const Server = struct {
    // Configuration
    config: Config,
    
    // State
    listener: std.net.StreamServer,
    running: std.atomic.Atomic(bool),
    connection_count: std.atomic.Atomic(usize),
    
    // Methods
    pub fn init(allocator: std.mem.Allocator, config: Config) !Server;
    pub fn deinit(self: *Server) void;
    pub fn start(self: *Server) !void;
    pub fn stop(self: *Server) void;
};
```

### Connection

```zig
pub const Connection = struct {
    // State
    server: *Server,
    stream: std.net.Stream,
    protocol: ?Protocol,
    
    // Methods
    pub fn init(server: *Server, stream: std.net.Stream) Connection;
    pub fn deinit(self: *Connection) void;
    pub fn handle(self: *Connection) !void;
};
```

### Thread Pool

```zig
pub const ThreadPool = struct {
    // Configuration
    thread_count: usize,
    
    // State
    threads: []std.Thread,
    tasks: std.fifo.LinearFifo(Task, .Dynamic),
    mutex: std.Thread.Mutex,
    condition: std.Thread.Condition,
    running: std.atomic.Atomic(bool),
    
    // Methods
    pub fn init(allocator: std.mem.Allocator, thread_count: usize) !ThreadPool;
    pub fn deinit(self: *ThreadPool) void;
    pub fn start(self: *ThreadPool) !void;
    pub fn stop(self: *ThreadPool) void;
    pub fn submit(self: *ThreadPool, task: Task) !void;
};
```

## Example Usage

```zig
// Initialize the server
var server = try Server.init(allocator, config);
defer server.deinit();

// Start the server
try server.start();

// Wait for a signal to stop
while (server.running.load(.SeqCst)) {
    std.time.sleep(1 * std.time.ns_per_s);
}

// Stop the server
server.stop();
```

## Server Extensions

The server component is designed to be extensible:

- **Protocol Handlers**: New protocol handlers can be added by implementing the protocol handler interface
- **Connection Handlers**: New connection handlers can be added by implementing the connection handler interface
- **Thread Pool**: The thread pool can be customized for different workloads

## Server Monitoring

The server component provides monitoring through:

- **Logging**: Detailed logs for debugging and auditing
- **Metrics**: Performance metrics for monitoring
- **Health Checks**: Endpoints for checking the server's health

## Server Security

The server component includes several security features:

- **TLS**: Support for secure connections
- **Connection Limits**: Limits on the number of connections to prevent resource exhaustion
- **Timeouts**: Timeouts to prevent resource exhaustion from slow clients
- **Error Handling**: Graceful handling of errors to prevent crashes
