const std = @import("std");
const config = @import("../config/config.zig");
const logger = @import("../utils/logger.zig");

// Forward declarations for middleware types
pub const RateLimitMiddleware = @import("rate_limit.zig").RateLimitMiddleware;
pub const AuthMiddleware = @import("auth.zig").AuthMiddleware;
pub const CorsMiddleware = @import("cors.zig").CorsMiddleware;
pub const CacheMiddleware = @import("cache.zig").CacheMiddleware;

/// Middleware result
pub const MiddlewareResult = struct {
    allowed: bool,
    reason: []const u8,

    pub fn deinit(self: *MiddlewareResult, allocator: std.mem.Allocator) void {
        allocator.free(self.reason);
    }
};

/// Middleware interface
pub const Middleware = struct {
    /// Apply the middleware to a request
    applyFn: *const fn (middleware: *Middleware, request: anytype, route: anytype) anyerror!MiddlewareResult,

    /// Initialize the middleware
    initFn: *const fn (allocator: std.mem.Allocator, middleware_config: std.json.Value) anyerror!*Middleware,

    /// Deinitialize the middleware
    deinitFn: *const fn (middleware: *Middleware) void,

    /// Apply the middleware to a request
    pub fn apply(self: *Middleware, request: anytype, route: anytype) !MiddlewareResult {
        return self.applyFn(self, request, route);
    }

    /// Initialize the middleware
    pub fn init(middleware_type: *Middleware, allocator: std.mem.Allocator, middleware_config: std.json.Value) !*Middleware {
        return middleware_type.initFn(allocator, middleware_config);
    }

    /// Deinitialize the middleware
    pub fn deinit(self: *Middleware) void {
        self.deinitFn(self);
    }
};

/// Middleware chain
pub const MiddlewareChain = struct {
    allocator: std.mem.Allocator,
    middlewares: std.ArrayList(*Middleware),

    /// Initialize the middleware chain
    pub fn init(allocator: std.mem.Allocator) !MiddlewareChain {
        return MiddlewareChain{
            .allocator = allocator,
            .middlewares = std.ArrayList(*Middleware).init(allocator),
        };
    }

    /// Initialize the middleware chain from configuration
    pub fn initFromConfig(allocator: std.mem.Allocator, middleware_config: []const config.MiddlewareConfig) !MiddlewareChain {
        var chain = try MiddlewareChain.init(allocator);
        errdefer chain.deinit();

        for (middleware_config) |mw_config| {
            const middleware_type = mw_config.type;

            // Create middleware based on type
            var middleware: *Middleware = undefined;

            if (std.mem.eql(u8, middleware_type, "rate_limit")) {
                middleware = try RateLimitMiddleware.init(allocator, mw_config.config);
            } else if (std.mem.eql(u8, middleware_type, "auth")) {
                middleware = try AuthMiddleware.init(allocator, mw_config.config);
            } else if (std.mem.eql(u8, middleware_type, "cors")) {
                middleware = try CorsMiddleware.init(allocator, mw_config.config);
            } else if (std.mem.eql(u8, middleware_type, "cache")) {
                middleware = try CacheMiddleware.init(allocator, mw_config.config);
            } else {
                logger.warning("Unknown middleware type: {s}", .{middleware_type});
                continue;
            }

            try chain.add(middleware);
        }

        return chain;
    }

    /// Add a middleware to the chain
    pub fn add(self: *MiddlewareChain, middleware: *Middleware) !void {
        try self.middlewares.append(middleware);
    }

    /// Apply all middlewares in the chain
    pub fn apply(self: *MiddlewareChain, request: anytype, route: anytype) !MiddlewareResult {
        for (self.middlewares.items) |middleware| {
            const result = try middleware.apply(request, route);

            if (!result.allowed) {
                return result;
            }
        }

        return MiddlewareResult{
            .allowed = true,
            .reason = try self.allocator.dupe(u8, ""),
        };
    }

    /// Clean up middleware chain resources
    pub fn deinit(self: *MiddlewareChain) void {
        for (self.middlewares.items) |middleware| {
            middleware.deinit();
        }

        self.middlewares.deinit();
    }
};

// Rate limiting middleware is now in rate_limit.zig

// Authentication middleware is now in auth.zig

// CORS middleware is now in cors.zig

// Cache middleware is now in cache.zig

// Helper functions are now in their respective middleware files

// Tests are now in their respective middleware files
