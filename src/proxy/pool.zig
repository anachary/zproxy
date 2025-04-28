const std = @import("std");
const logger = @import("../utils/logger.zig");
const upstream = @import("upstream.zig");

/// Pooled connection
pub const PooledConnection = struct {
    stream: std.net.Stream,
    upstream_host: []const u8,
    upstream_port: u16,
    in_use: bool,
    last_used: i64,
    
    pub fn deinit(self: *PooledConnection) void {
        self.stream.close();
    }
};

/// Connection pool
pub const ConnectionPool = struct {
    allocator: std.mem.Allocator,
    connections: []PooledConnection,
    mutex: std.Thread.Mutex,
    max_connections: u32,
    
    /// Initialize a new connection pool
    pub fn init(allocator: std.mem.Allocator, max_connections: u32) !ConnectionPool {
        var connections = try allocator.alloc(PooledConnection, max_connections);
        
        // Initialize connections as not in use
        for (connections) |*conn| {
            conn.in_use = false;
            conn.last_used = 0;
        }
        
        return ConnectionPool{
            .allocator = allocator,
            .connections = connections,
            .mutex = std.Thread.Mutex{},
            .max_connections = max_connections,
        };
    }
    
    /// Clean up connection pool resources
    pub fn deinit(self: *ConnectionPool) void {
        // Close all connections
        for (self.connections) |*conn| {
            if (conn.in_use or conn.last_used > 0) {
                conn.deinit();
            }
        }
        
        // Free connections array
        self.allocator.free(self.connections);
    }
    
    /// Get a connection from the pool
    pub fn getConnection(self: *ConnectionPool, upstream_info: upstream.UpstreamInfo) !PooledConnection {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Try to find an existing connection
        for (self.connections) |*conn| {
            if (!conn.in_use and conn.last_used > 0 and
                std.mem.eql(u8, conn.upstream_host, upstream_info.host) and
                conn.upstream_port == upstream_info.port)
            {
                // Found an existing connection
                conn.in_use = true;
                return conn.*;
            }
        }
        
        // Try to find an unused slot
        for (self.connections) |*conn| {
            if (!conn.in_use and conn.last_used == 0) {
                // Create a new connection
                const address = try std.net.Address.parseIp(upstream_info.host, upstream_info.port);
                const stream = try std.net.tcpConnectToAddress(address);
                
                conn.* = PooledConnection{
                    .stream = stream,
                    .upstream_host = upstream_info.host,
                    .upstream_port = upstream_info.port,
                    .in_use = true,
                    .last_used = std.time.milliTimestamp(),
                };
                
                return conn.*;
            }
        }
        
        // Find the oldest connection and reuse it
        var oldest_index: usize = 0;
        var oldest_time: i64 = std.time.milliTimestamp();
        
        for (self.connections, 0..) |conn, i| {
            if (!conn.in_use and conn.last_used < oldest_time) {
                oldest_index = i;
                oldest_time = conn.last_used;
            }
        }
        
        // Close the oldest connection
        if (self.connections[oldest_index].last_used > 0) {
            self.connections[oldest_index].deinit();
        }
        
        // Create a new connection
        const address = try std.net.Address.parseIp(upstream_info.host, upstream_info.port);
        const stream = try std.net.tcpConnectToAddress(address);
        
        self.connections[oldest_index] = PooledConnection{
            .stream = stream,
            .upstream_host = upstream_info.host,
            .upstream_port = upstream_info.port,
            .in_use = true,
            .last_used = std.time.milliTimestamp(),
        };
        
        return self.connections[oldest_index];
    }
    
    /// Release a connection back to the pool
    pub fn releaseConnection(self: *ConnectionPool, conn: PooledConnection) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Find the connection in the pool
        for (self.connections) |*pool_conn| {
            if (pool_conn.in_use and
                std.mem.eql(u8, pool_conn.upstream_host, conn.upstream_host) and
                pool_conn.upstream_port == conn.upstream_port)
            {
                // Release the connection
                pool_conn.in_use = false;
                pool_conn.last_used = std.time.milliTimestamp();
                return;
            }
        }
        
        // Connection not found in the pool, close it
        var mutable_conn = conn;
        mutable_conn.deinit();
    }
};
