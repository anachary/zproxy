const std = @import("std");
const defaults = @import("defaults.zig");

/// Configuration for the gateway
pub const Config = struct {
    allocator: std.mem.Allocator,
    listen_address: []const u8,
    listen_port: u16,
    routes: []Route,
    tls: TlsConfig,
    middleware: MiddlewareConfig,

    /// Initialize a new Config with default values
    pub fn init(allocator: std.mem.Allocator) !Config {
        const listen_address = try allocator.dupe(u8, defaults.listen_address);
        const routes = try allocator.alloc(Route, 0);

        return Config{
            .allocator = allocator,
            .listen_address = listen_address,
            .listen_port = defaults.listen_port,
            .routes = routes,
            .tls = TlsConfig.init(),
            .middleware = MiddlewareConfig.init(),
        };
    }

    /// Load configuration from a JSON file
    pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Config {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const buffer = try allocator.alloc(u8, file_size);
        defer allocator.free(buffer);

        const bytes_read = try file.readAll(buffer);
        if (bytes_read != file_size) {
            return error.IncompleteRead;
        }

        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
        defer parsed.deinit();

        return try parseConfig(allocator, parsed.value);
    }

    /// Parse configuration from a JSON value
    fn parseConfig(allocator: std.mem.Allocator, root: std.json.Value) !Config {
        var config = try Config.init(allocator);
        errdefer config.deinit();

        // Parse listen address and port
        if (root.object.get("listen_address")) |addr| {
            allocator.free(config.listen_address);
            config.listen_address = try allocator.dupe(u8, addr.string);
        }

        if (root.object.get("listen_port")) |port| {
            config.listen_port = @intCast(port.integer);
        }

        // Parse routes
        if (root.object.get("routes")) |routes_json| {
            allocator.free(config.routes);
            config.routes = try parseRoutes(allocator, routes_json);
        }

        // Parse TLS config
        if (root.object.get("tls")) |tls_json| {
            config.tls = try TlsConfig.parse(allocator, tls_json);
        }

        // Parse middleware config
        if (root.object.get("middleware")) |middleware_json| {
            config.middleware = try MiddlewareConfig.parse(allocator, middleware_json);
        }

        return config;
    }

    /// Clean up resources
    pub fn deinit(self: *Config) void {
        self.allocator.free(self.listen_address);

        for (self.routes) |*route| {
            route.deinit(self.allocator);
        }
        self.allocator.free(self.routes);

        self.tls.deinit(self.allocator);
        self.middleware.deinit(self.allocator);
    }
};

/// Configuration for a route
pub const Route = struct {
    path: []const u8,
    upstream: []const u8,
    methods: []const []const u8,
    middleware: []const []const u8,

    /// Initialize a new Route
    pub fn init(
        allocator: std.mem.Allocator,
        path: []const u8,
        upstream: []const u8,
        methods: []const []const u8,
        middleware: []const []const u8,
    ) !Route {
        const path_copy = try allocator.dupe(u8, path);
        const upstream_copy = try allocator.dupe(u8, upstream);

        const methods_copy = try allocator.alloc([]const u8, methods.len);
        errdefer allocator.free(methods_copy);

        for (methods, 0..) |method, i| {
            methods_copy[i] = try allocator.dupe(u8, method);
        }

        const middleware_copy = try allocator.alloc([]const u8, middleware.len);
        errdefer {
            for (methods_copy) |method| {
                allocator.free(method);
            }
            allocator.free(middleware_copy);
        }

        for (middleware, 0..) |mw, i| {
            middleware_copy[i] = try allocator.dupe(u8, mw);
        }

        return Route{
            .path = path_copy,
            .upstream = upstream_copy,
            .methods = methods_copy,
            .middleware = middleware_copy,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Route, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.upstream);

        for (self.methods) |method| {
            allocator.free(method);
        }
        allocator.free(self.methods);

        for (self.middleware) |mw| {
            allocator.free(mw);
        }
        allocator.free(self.middleware);
    }
};

/// Parse routes from JSON
fn parseRoutes(allocator: std.mem.Allocator, routes_json: std.json.Value) ![]Route {
    const routes_array = routes_json.array;
    var routes = try allocator.alloc(Route, routes_array.items.len);
    errdefer allocator.free(routes);

    for (routes_array.items, 0..) |route_json, i| {
        const path = route_json.object.get("path").?.string;
        const upstream = route_json.object.get("upstream").?.string;

        // Parse methods
        const methods_json = route_json.object.get("methods").?.array;
        var methods = try allocator.alloc([]const u8, methods_json.items.len);
        errdefer allocator.free(methods);

        for (methods_json.items, 0..) |method_json, j| {
            methods[j] = try allocator.dupe(u8, method_json.string);
        }

        // Parse middleware
        const middleware_json = route_json.object.get("middleware").?.array;
        var middleware = try allocator.alloc([]const u8, middleware_json.items.len);
        errdefer {
            for (methods) |method| {
                allocator.free(method);
            }
            allocator.free(middleware);
        }

        for (middleware_json.items, 0..) |mw_json, j| {
            middleware[j] = try allocator.dupe(u8, mw_json.string);
        }

        routes[i] = Route{
            .path = try allocator.dupe(u8, path),
            .upstream = try allocator.dupe(u8, upstream),
            .methods = methods,
            .middleware = middleware,
        };
    }

    return routes;
}

/// TLS configuration
pub const TlsConfig = struct {
    enabled: bool,
    cert_path: ?[]const u8,
    key_path: ?[]const u8,

    /// Initialize with default values
    pub fn init() TlsConfig {
        return TlsConfig{
            .enabled = defaults.tls_enabled,
            .cert_path = null,
            .key_path = null,
        };
    }

    /// Parse TLS config from JSON
    pub fn parse(allocator: std.mem.Allocator, json: std.json.Value) !TlsConfig {
        var config = TlsConfig.init();

        if (json.object.get("enabled")) |enabled| {
            config.enabled = enabled.bool;
        }

        if (json.object.get("cert_path")) |cert_path| {
            config.cert_path = try allocator.dupe(u8, cert_path.string);
        }

        if (json.object.get("key_path")) |key_path| {
            config.key_path = try allocator.dupe(u8, key_path.string);
        }

        return config;
    }

    /// Clean up resources
    pub fn deinit(self: *TlsConfig, allocator: std.mem.Allocator) void {
        if (self.cert_path) |cert_path| {
            allocator.free(cert_path);
            self.cert_path = null;
        }

        if (self.key_path) |key_path| {
            allocator.free(key_path);
            self.key_path = null;
        }
    }
};

/// Middleware configuration
pub const MiddlewareConfig = struct {
    rate_limit: RateLimitConfig,
    auth: AuthConfig,
    cache: CacheConfig,

    /// Initialize with default values
    pub fn init() MiddlewareConfig {
        return MiddlewareConfig{
            .rate_limit = RateLimitConfig.init(),
            .auth = AuthConfig.init(),
            .cache = CacheConfig.init(),
        };
    }

    /// Parse middleware config from JSON
    pub fn parse(allocator: std.mem.Allocator, json: std.json.Value) !MiddlewareConfig {
        var config = MiddlewareConfig.init();

        if (json.object.get("rate_limit")) |rate_limit| {
            config.rate_limit = try RateLimitConfig.parse(rate_limit);
        }

        if (json.object.get("auth")) |auth| {
            config.auth = try AuthConfig.parse(allocator, auth);
        }

        if (json.object.get("cache")) |cache| {
            config.cache = try CacheConfig.parse(cache);
        }

        return config;
    }

    /// Clean up resources
    pub fn deinit(self: *MiddlewareConfig, allocator: std.mem.Allocator) void {
        self.auth.deinit(allocator);
    }
};

/// Rate limiting configuration
pub const RateLimitConfig = struct {
    enabled: bool,
    requests_per_minute: u32,

    /// Initialize with default values
    pub fn init() RateLimitConfig {
        return RateLimitConfig{
            .enabled = defaults.rate_limit_enabled,
            .requests_per_minute = defaults.rate_limit_requests_per_minute,
        };
    }

    /// Parse rate limit config from JSON
    pub fn parse(json: std.json.Value) !RateLimitConfig {
        var config = RateLimitConfig.init();

        if (json.object.get("enabled")) |enabled| {
            config.enabled = enabled.bool;
        }

        if (json.object.get("requests_per_minute")) |rpm| {
            config.requests_per_minute = @intCast(rpm.integer);
        }

        return config;
    }
};

/// Authentication configuration
pub const AuthConfig = struct {
    enabled: bool,
    jwt_secret: ?[]const u8,

    /// Initialize with default values
    pub fn init() AuthConfig {
        return AuthConfig{
            .enabled = defaults.auth_enabled,
            .jwt_secret = null,
        };
    }

    /// Parse auth config from JSON
    pub fn parse(allocator: std.mem.Allocator, json: std.json.Value) !AuthConfig {
        var config = AuthConfig.init();

        if (json.object.get("enabled")) |enabled| {
            config.enabled = enabled.bool;
        }

        if (json.object.get("jwt_secret")) |secret| {
            config.jwt_secret = try allocator.dupe(u8, secret.string);
        }

        return config;
    }

    /// Clean up resources
    pub fn deinit(self: *AuthConfig, allocator: std.mem.Allocator) void {
        if (self.jwt_secret) |secret| {
            allocator.free(secret);
            self.jwt_secret = null;
        }
    }
};

/// Cache configuration
pub const CacheConfig = struct {
    enabled: bool,
    ttl_seconds: u32,

    /// Initialize with default values
    pub fn init() CacheConfig {
        return CacheConfig{
            .enabled = defaults.cache_enabled,
            .ttl_seconds = defaults.cache_ttl_seconds,
        };
    }

    /// Parse cache config from JSON
    pub fn parse(json: std.json.Value) !CacheConfig {
        var config = CacheConfig.init();

        if (json.object.get("enabled")) |enabled| {
            config.enabled = enabled.bool;
        }

        if (json.object.get("ttl_seconds")) |ttl| {
            config.ttl_seconds = @intCast(ttl.integer);
        }

        return config;
    }
};

// Tests
test "Config initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = try Config.init(allocator);
    defer config.deinit();

    try testing.expectEqualStrings(defaults.listen_address, config.listen_address);
    try testing.expectEqual(@as(u16, defaults.listen_port), config.listen_port);
    try testing.expectEqual(@as(usize, 0), config.routes.len);
    try testing.expectEqual(defaults.tls_enabled, config.tls.enabled);
    try testing.expectEqual(defaults.rate_limit_enabled, config.middleware.rate_limit.enabled);
}
