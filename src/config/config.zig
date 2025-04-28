const std = @import("std");

/// Protocol types supported by ZProxy
pub const Protocol = enum {
    http1,
    http2,
    websocket,
};

/// Middleware configuration
pub const MiddlewareConfig = struct {
    type: []const u8,
    config: std.json.Value,

    pub fn deinit(self: *MiddlewareConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        // The config value is freed separately
    }
};

/// TLS configuration
pub const TlsConfig = struct {
    enabled: bool,
    cert_file: ?[]const u8,
    key_file: ?[]const u8,

    pub fn deinit(self: *TlsConfig, allocator: std.mem.Allocator) void {
        if (self.cert_file) |cert_file| {
            allocator.free(cert_file);
        }
        if (self.key_file) |key_file| {
            allocator.free(key_file);
        }
    }
};

/// Route configuration
pub const Route = struct {
    path: []const u8,
    upstream: []const u8,
    methods: []const []const u8,

    pub fn deinit(self: *Route, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.upstream);

        for (self.methods) |method| {
            allocator.free(method);
        }
        allocator.free(self.methods);
    }
};

/// Main configuration structure
pub const Config = struct {
    // Server configuration
    host: []const u8,
    port: u16,

    // Performance configuration
    thread_count: u32,
    backlog: u32,
    max_connections: u32,
    connection_timeout_ms: u32,

    // Protocol configuration
    protocols: []const Protocol,

    // TLS configuration
    tls: TlsConfig,

    // Routing configuration
    routes: []Route,

    // Middleware configuration
    middlewares: []MiddlewareConfig,

    // Store the allocator for cleanup
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        const allocator = self.allocator;

        allocator.free(self.host);
        allocator.free(self.protocols);

        self.tls.deinit(allocator);

        for (self.routes) |*route| {
            route.deinit(allocator);
        }
        allocator.free(self.routes);

        for (self.middlewares) |*middleware| {
            middleware.deinit(allocator);
        }
        allocator.free(self.middlewares);
    }
};

// Configuration loading is now in loader.zig

/// Get default configuration
pub fn getDefaultConfig(allocator: std.mem.Allocator) Config {
    const host = allocator.dupe(u8, "127.0.0.1") catch unreachable;

    var protocols = allocator.alloc(Protocol, 1) catch unreachable;
    protocols[0] = .http1;

    var routes = allocator.alloc(Route, 1) catch unreachable;

    const path = allocator.dupe(u8, "/") catch unreachable;
    const upstream = allocator.dupe(u8, "http://127.0.0.1:8080") catch unreachable;

    var methods = allocator.alloc([]const u8, 1) catch unreachable;
    methods[0] = allocator.dupe(u8, "GET") catch unreachable;

    routes[0] = Route{
        .path = path,
        .upstream = upstream,
        .methods = methods,
    };

    // Create default middleware configuration
    var middlewares = allocator.alloc(MiddlewareConfig, 0) catch unreachable;

    return Config{
        .host = host,
        .port = 8000,
        .thread_count = 4,
        .backlog = 128,
        .max_connections = 1000,
        .connection_timeout_ms = 30000,
        .protocols = protocols,
        .tls = TlsConfig{
            .enabled = false,
            .cert_file = null,
            .key_file = null,
        },
        .routes = routes,
        .middlewares = middlewares,
        .allocator = allocator,
    };
}

test "Config - Default Configuration" {
    const testing = std.testing;
    var config = getDefaultConfig(testing.allocator);
    defer config.deinit();

    try testing.expectEqualStrings("127.0.0.1", config.host);
    try testing.expectEqual(@as(u16, 8000), config.port);
    try testing.expectEqual(@as(u32, 4), config.thread_count);
    try testing.expectEqual(@as(u32, 128), config.backlog);
    try testing.expectEqual(@as(u32, 1000), config.max_connections);
    try testing.expectEqual(@as(u32, 30000), config.connection_timeout_ms);

    try testing.expectEqual(@as(usize, 1), config.protocols.len);
    try testing.expectEqual(Protocol.http1, config.protocols[0]);

    try testing.expectEqual(false, config.tls.enabled);
    try testing.expectEqual(@as(?[]const u8, null), config.tls.cert_file);
    try testing.expectEqual(@as(?[]const u8, null), config.tls.key_file);

    try testing.expectEqual(@as(usize, 1), config.routes.len);
    try testing.expectEqualStrings("/", config.routes[0].path);
    try testing.expectEqualStrings("http://127.0.0.1:8080", config.routes[0].upstream);
    try testing.expectEqual(@as(usize, 1), config.routes[0].methods.len);
    try testing.expectEqualStrings("GET", config.routes[0].methods[0]);

    try testing.expectEqual(@as(usize, 0), config.middlewares.len);
}
