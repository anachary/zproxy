const std = @import("std");
const utils = @import("../utils/allocator.zig");

/// A connection to an upstream server
pub const Connection = struct {
    stream: std.net.Stream,
    address: std.net.Address,
    pool: *ConnectionPool,
    id: usize,

    /// Close the connection
    pub fn close(self: *Connection) void {
        self.stream.close();
    }

    /// Return the connection to the pool
    pub fn release(self: *Connection) void {
        self.pool.returnConnection(self);
    }
};

/// A pool of connections to an upstream server
pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    upstream_url: []const u8,
    max_connections: usize,
    idle_timeout_ms: u64,
    connections: std.ArrayList(PooledConnection),
    mutex: std.Thread.Mutex,
    connection_semaphore: std.Thread.Semaphore,
    next_conn_id: std.atomic.Atomic(usize),
    uri: std.Uri,
    host: []const u8,
    port: u16,
    is_https: bool,

    /// A connection in the pool
    const PooledConnection = struct {
        connection: Connection,
        last_used: i64,
        in_use: bool,
        id: usize,

        /// Check if the connection is idle for too long
        fn isIdle(self: *const PooledConnection, now: i64, timeout_ms: u64) bool {
            return !self.in_use and now - self.last_used > timeout_ms;
        }
    };

    /// Initialize a new connection pool
    pub fn init(allocator: std.mem.Allocator, upstream_url: []const u8) !ConnectionPool {
        // Parse the URL once during initialization
        var uri = try std.Uri.parse(upstream_url);
        const host = uri.host orelse return error.InvalidUpstreamUrl;
        const host_copy = try allocator.dupe(u8, host);
        const port = uri.port orelse if (std.mem.eql(u8, uri.scheme, "https")) 443 else 80;
        const is_https = std.mem.eql(u8, uri.scheme, "https");

        return ConnectionPool{
            .allocator = allocator,
            .upstream_url = try allocator.dupe(u8, upstream_url),
            .max_connections = 100, // Increased from 10
            .idle_timeout_ms = 60000, // Increased to 60 seconds
            .connections = std.ArrayList(PooledConnection).init(allocator),
            .mutex = std.Thread.Mutex{},
            .connection_semaphore = std.Thread.Semaphore{},
            .next_conn_id = std.atomic.Atomic(usize).init(0),
            .uri = uri,
            .host = host_copy,
            .port = port,
            .is_https = is_https,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *ConnectionPool) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |*conn| {
            conn.connection.close();
        }

        self.connections.deinit();
        self.allocator.free(self.upstream_url);
        self.allocator.free(self.host);
    }

    /// Get a connection from the pool
    pub fn getConnection(self: *ConnectionPool) !Connection {
        // Fast path: try to get a connection without locking
        var conn = self.tryGetIdleConnection();
        if (conn) |connection| {
            return connection;
        }

        // Slow path: need to create a new connection
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up idle connections
        try self.cleanupIdleConnections();

        // Try to find an existing connection that's not in use
        for (self.connections.items) |*conn_item| {
            if (!conn_item.in_use) {
                conn_item.in_use = true;
                conn_item.last_used = std.time.milliTimestamp();

                // Create a new connection object that references the pooled connection
                return Connection{
                    .stream = conn_item.connection.stream,
                    .address = conn_item.connection.address,
                    .pool = self,
                    .id = conn_item.id,
                };
            }
        }

        // If we have reached the maximum number of connections, wait for one to become available
        if (self.connections.items.len >= self.max_connections) {
            // Instead of returning an error, we'll wait for a connection to become available
            self.mutex.unlock(); // Unlock before waiting
            self.connection_semaphore.wait(); // Wait for a connection to be returned
            self.mutex.lock(); // Lock again after waking up

            // Try again to find an idle connection
            for (self.connections.items) |*conn_item| {
                if (!conn_item.in_use) {
                    conn_item.in_use = true;
                    conn_item.last_used = std.time.milliTimestamp();

                    return Connection{
                        .stream = conn_item.connection.stream,
                        .address = conn_item.connection.address,
                        .pool = self,
                        .id = conn_item.id,
                    };
                }
            }
        }

        // Create a new connection
        const address = try std.net.Address.parseIp(self.host, self.port);
        var stream = try std.net.tcpConnectToAddress(address);

        // Set TCP options for better performance
        try stream.setNoDelay(true); // Disable Nagle's algorithm
        try stream.setTcpKeepAlive(true);

        // Get a new connection ID
        const conn_id = self.next_conn_id.fetchAdd(1, .Monotonic);

        // Create the connection object
        var connection = Connection{
            .stream = stream,
            .address = address,
            .pool = self,
            .id = conn_id,
        };

        // Add the connection to the pool
        try self.connections.append(PooledConnection{
            .connection = connection,
            .last_used = std.time.milliTimestamp(),
            .in_use = true,
            .id = conn_id,
        });

        // Return the connection
        return connection;
    }

    /// Try to get an idle connection without locking (for fast path)
    fn tryGetIdleConnection(self: *ConnectionPool) ?Connection {
        // Use atomic operations to check if there are any connections
        if (self.connections.items.len == 0) {
            return null;
        }

        // Try to find an idle connection with minimal locking
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.connections.items) |*conn| {
            if (!conn.in_use) {
                conn.in_use = true;
                conn.last_used = std.time.milliTimestamp();

                return Connection{
                    .stream = conn.connection.stream,
                    .address = conn.connection.address,
                    .pool = self,
                    .id = conn.id,
                };
            }
        }

        return null;
    }

    /// Return a connection to the pool
    pub fn returnConnection(self: *ConnectionPool, connection: *Connection) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find the connection in the pool by ID (faster than comparing handles)
        for (self.connections.items) |*conn| {
            if (conn.id == connection.id) {
                conn.in_use = false;
                conn.last_used = std.time.milliTimestamp();

                // Signal that a connection is available
                self.connection_semaphore.post();
                return;
            }
        }

        // If the connection is not in the pool, close it
        connection.close();
    }

    /// Clean up idle connections
    fn cleanupIdleConnections(self: *ConnectionPool) !void {
        const now = std.time.milliTimestamp();
        var i: usize = 0;

        // Keep at least some connections in the pool for reuse
        const min_idle_connections = 5;
        var idle_count: usize = 0;

        // First count idle connections
        for (self.connections.items) |conn| {
            if (!conn.in_use) {
                idle_count += 1;
            }
        }

        // Only clean up if we have more than the minimum
        if (idle_count <= min_idle_connections) {
            return;
        }

        // Now remove excess idle connections
        while (i < self.connections.items.len) {
            const conn = &self.connections.items[i];

            if (conn.isIdle(now, self.idle_timeout_ms) and idle_count > min_idle_connections) {
                // Close the connection
                conn.connection.close();

                // Remove from the pool
                _ = self.connections.swapRemove(i);

                // Decrement idle count
                idle_count -= 1;
            } else {
                i += 1;
            }
        }
    }

    /// Pre-warm the connection pool by creating some connections in advance
    pub fn preWarm(self: *ConnectionPool, count: usize) !void {
        const actual_count = @min(count, self.max_connections);
        var connections = try self.allocator.alloc(Connection, actual_count);
        defer self.allocator.free(connections);

        // Create connections
        for (0..actual_count) |i| {
            connections[i] = try self.getConnection();
        }

        // Return them to the pool
        for (0..actual_count) |i| {
            self.returnConnection(&connections[i]);
        }
    }
};
