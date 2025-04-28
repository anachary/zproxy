const std = @import("std");
const logger = @import("../utils/logger.zig");
const upstream = @import("upstream.zig");
const pool = @import("pool.zig");

/// Proxy configuration
pub const ProxyConfig = struct {
    timeout_ms: u32 = 30000,
    max_retries: u32 = 3,
    retry_delay_ms: u32 = 1000,
    connection_pool_size: u32 = 10,
};

/// Proxy request
pub const ProxyRequest = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    pub fn deinit(self: *ProxyRequest, allocator: std.mem.Allocator) void {
        var headers_it = self.headers.iterator();
        while (headers_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }
};

/// Proxy response
pub const ProxyResponse = struct {
    status_code: u16,
    status_text: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    pub fn deinit(self: *ProxyResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.status_text);
        allocator.free(self.body);

        var headers_it = self.headers.iterator();
        while (headers_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
    }
};

/// Proxy error
pub const ProxyError = error{
    ConnectionFailed,
    RequestFailed,
    ResponseFailed,
    Timeout,
    InvalidUpstream,
    PoolExhausted,
};

/// Proxy for forwarding requests to upstream servers
pub const Proxy = struct {
    allocator: std.mem.Allocator,
    config: ProxyConfig,
    connection_pool: pool.ConnectionPool,

    /// Initialize a new proxy
    pub fn init(allocator: std.mem.Allocator, config: ProxyConfig) !Proxy {
        var connection_pool = try pool.ConnectionPool.init(allocator, config.connection_pool_size);

        return Proxy{
            .allocator = allocator,
            .config = config,
            .connection_pool = connection_pool,
        };
    }

    /// Clean up proxy resources
    pub fn deinit(self: *Proxy) void {
        self.connection_pool.deinit();
    }

    /// Forward a request to an upstream server
    pub fn forward(self: *Proxy, upstream_url: []const u8, request: ProxyRequest) !ProxyResponse {
        logger.debug("Forwarding request to {s}", .{upstream_url});

        // Parse upstream URL
        const upstream_info = try upstream.parseUpstreamUrl(self.allocator, upstream_url);
        defer upstream_info.deinit(self.allocator);

        // Get a connection from the pool
        var conn = try self.connection_pool.getConnection(upstream_info);
        defer self.connection_pool.releaseConnection(conn);

        // Set timeout
        try conn.stream.setReadTimeout(self.config.timeout_ms * std.time.ns_per_ms);
        try conn.stream.setWriteTimeout(self.config.timeout_ms * std.time.ns_per_ms);

        // Send request
        try self.sendRequest(conn, upstream_info, request);

        // Receive response
        return try self.receiveResponse(conn);
    }

    /// Send a request to an upstream server
    fn sendRequest(self: *Proxy, conn: pool.PooledConnection, upstream_info: upstream.UpstreamInfo, request: ProxyRequest) !void {
        // Build request line
        var request_line = try std.fmt.allocPrint(
            self.allocator,
            "{s} {s} HTTP/1.1\r\n",
            .{ request.method, request.path },
        );
        defer self.allocator.free(request_line);

        // Send request line
        _ = try conn.stream.write(request_line);

        // Send Host header if not present
        if (!request.headers.contains("Host")) {
            var host_header = try std.fmt.allocPrint(
                self.allocator,
                "Host: {s}\r\n",
                .{upstream_info.host},
            );
            defer self.allocator.free(host_header);
            _ = try conn.stream.write(host_header);
        }

        // Send headers
        var headers_it = request.headers.iterator();
        while (headers_it.next()) |entry| {
            var header_line = try std.fmt.allocPrint(
                self.allocator,
                "{s}: {s}\r\n",
                .{ entry.key_ptr.*, entry.value_ptr.* },
            );
            defer self.allocator.free(header_line);
            _ = try conn.stream.write(header_line);
        }

        // Send Content-Length header if not present and body is not empty
        if (!request.headers.contains("Content-Length") and request.body.len > 0) {
            var content_length_header = try std.fmt.allocPrint(
                self.allocator,
                "Content-Length: {d}\r\n",
                .{request.body.len},
            );
            defer self.allocator.free(content_length_header);
            _ = try conn.stream.write(content_length_header);
        }

        // Send empty line to separate headers from body
        _ = try conn.stream.write("\r\n");

        // Send body if not empty
        if (request.body.len > 0) {
            _ = try conn.stream.write(request.body);
        }
    }

    /// Receive a response from an upstream server
    fn receiveResponse(self: *Proxy, conn: pool.PooledConnection) !ProxyResponse {
        // Read response
        var buffer: [8192]u8 = undefined;
        const bytes_read = try conn.stream.read(&buffer);

        if (bytes_read == 0) {
            return ProxyError.ResponseFailed;
        }

        // Parse status line
        const status_line_end = std.mem.indexOf(u8, buffer[0..bytes_read], "\r\n") orelse return ProxyError.ResponseFailed;
        const status_line = buffer[0..status_line_end];

        // Split status line
        var status_line_it = std.mem.split(u8, status_line, " ");
        const version = status_line_it.next() orelse return ProxyError.ResponseFailed;
        const status_code_str = status_line_it.next() orelse return ProxyError.ResponseFailed;

        // Check HTTP version
        if (!std.mem.eql(u8, version, "HTTP/1.1") and !std.mem.eql(u8, version, "HTTP/1.0")) {
            return ProxyError.ResponseFailed;
        }

        // Parse status code
        const status_code = try std.fmt.parseInt(u16, status_code_str, 10);

        // Parse status text
        var status_text = status_line_it.rest();

        // Parse headers
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            var headers_it = headers.iterator();
            while (headers_it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            headers.deinit();
        }

        var headers_end = std.mem.indexOf(u8, buffer[status_line_end + 2 .. bytes_read], "\r\n\r\n") orelse return ProxyError.ResponseFailed;
        headers_end += status_line_end + 2;

        var header_start = status_line_end + 2;
        while (header_start < headers_end) {
            const header_end = std.mem.indexOf(u8, buffer[header_start..headers_end], "\r\n") orelse break;
            const header_line = buffer[header_start .. header_start + header_end];

            const colon_pos = std.mem.indexOf(u8, header_line, ":") orelse return ProxyError.ResponseFailed;
            const header_name = std.mem.trim(u8, header_line[0..colon_pos], " ");
            const header_value = std.mem.trim(u8, header_line[colon_pos + 1 ..], " ");

            try headers.put(
                try self.allocator.dupe(u8, header_name),
                try self.allocator.dupe(u8, header_value),
            );

            header_start += header_end + 2;
        }

        // Parse body
        const body_start = headers_end + 4;
        const body = buffer[body_start..bytes_read];

        return ProxyResponse{
            .status_code = status_code,
            .status_text = try self.allocator.dupe(u8, status_text),
            .headers = headers,
            .body = try self.allocator.dupe(u8, body),
        };
    }
};
