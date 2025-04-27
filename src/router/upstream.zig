const std = @import("std");

/// A connection to an upstream server
pub const Connection = struct {
    stream: std.net.Stream,
    address: std.net.Address,

    /// Close the connection
    pub fn close(self: *Connection) void {
        self.stream.close();
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

    /// A connection in the pool
    const PooledConnection = struct {
        connection: Connection,
        last_used: i64,
        in_use: bool,
    };

    /// Initialize a new connection pool
    pub fn init(allocator: std.mem.Allocator, upstream_url: []const u8) !ConnectionPool {
        return ConnectionPool{
            .allocator = allocator,
            .upstream_url = try allocator.dupe(u8, upstream_url),
            .max_connections = 10,
            .idle_timeout_ms = 30000, // 30 seconds
            .connections = std.ArrayList(PooledConnection).init(allocator),
            .mutex = std.Thread.Mutex{},
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
    }

    /// Get a connection from the pool
    pub fn getConnection(self: *ConnectionPool) !Connection {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up idle connections
        try self.cleanupIdleConnections();

        // Try to find an existing connection that's not in use
        for (self.connections.items) |*conn| {
            if (!conn.in_use) {
                conn.in_use = true;
                conn.last_used = std.time.milliTimestamp();

                // Create a new connection object that references the pooled connection
                return Connection{
                    .stream = conn.connection.stream,
                    .address = conn.connection.address,
                };
            }
        }

        // If we have reached the maximum number of connections, wait for one to become available
        if (self.connections.items.len >= self.max_connections) {
            return error.NoConnectionsAvailable;
        }

        // Create a new connection
        var uri = try std.Uri.parse(self.upstream_url);

        const host = uri.host orelse return error.InvalidUpstreamUrl;
        const port = uri.port orelse if (std.mem.eql(u8, uri.scheme, "https")) 443 else 80;

        const address = try std.net.Address.parseIp(host, port);
        const stream = try std.net.tcpConnectToAddress(address);

        // Add the connection to the pool
        try self.connections.append(PooledConnection{
            .connection = Connection{
                .stream = stream,
                .address = address,
            },
            .last_used = std.time.milliTimestamp(),
            .in_use = true,
        });

        // Return a new connection object
        return Connection{
            .stream = stream,
            .address = address,
        };
    }

    /// Return a connection to the pool
    pub fn returnConnection(self: *ConnectionPool, connection: *Connection) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Find the connection in the pool
        for (self.connections.items) |*conn| {
            if (conn.connection.stream.handle == connection.stream.handle) {
                conn.in_use = false;
                conn.last_used = std.time.milliTimestamp();
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

        while (i < self.connections.items.len) {
            const conn = &self.connections.items[i];

            if (!conn.in_use and now - conn.last_used > self.idle_timeout_ms) {
                // Close the connection
                conn.connection.close();

                // Remove from the pool
                _ = self.connections.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }
};
