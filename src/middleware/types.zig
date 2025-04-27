const std = @import("std");

// Re-export middleware modules
pub const chain = @import("chain.zig");
pub const ratelimit = @import("ratelimit.zig");
pub const jwt = @import("auth/jwt.zig");
pub const acl = @import("auth/acl.zig");
pub const cache = @import("cache/cache.zig");

/// Generic HTTP request interface
pub const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
};

/// Generic route interface
pub const Route = struct {
    path: []const u8,
    upstream: []const u8,
};

/// Middleware context for HTTP requests
pub const Context = struct {
    allocator: std.mem.Allocator,
    request: *const HttpRequest,
    route: *const Route,
    params: std.StringHashMap([]const u8),

    /// Initialize a new middleware context
    pub fn init(
        allocator: std.mem.Allocator,
        request: *const HttpRequest,
        route: *const Route,
    ) !Context {
        return Context{
            .allocator = allocator,
            .request = request,
            .route = route,
            .params = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Context) void {
        var it = self.params.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.params.deinit();
    }
};

/// Result of middleware execution
pub const Result = struct {
    success: bool,
    status_code: u16 = 200,
    error_message: []const u8 = "",
};

/// Middleware interface
pub const Middleware = struct {
    /// Process a request
    pub fn process(self: *const Middleware, context: *Context) !Result {
        _ = self;
        _ = context;
        return Result{ .success = true };
    }
};

/// Create a middleware instance by name
pub fn createMiddleware(
    allocator: std.mem.Allocator,
    name: []const u8,
    config: anytype,
) !*Middleware {
    if (std.mem.eql(u8, name, "ratelimit")) {
        return try ratelimit.RateLimitMiddleware.create(allocator, config);
    } else if (std.mem.eql(u8, name, "jwt")) {
        return try jwt.JwtMiddleware.create(allocator, config);
    } else if (std.mem.eql(u8, name, "acl")) {
        return try acl.AclMiddleware.create(allocator, config);
    } else if (std.mem.eql(u8, name, "cache")) {
        return try cache.CacheMiddleware.create(allocator, config);
    } else {
        return error.UnknownMiddleware;
    }
}
