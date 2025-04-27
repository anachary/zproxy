const std = @import("std");
const matcher = @import("matcher.zig");
const upstream_mod = @import("upstream.zig");

/// Route configuration for initialization
pub const RouteConfig = struct {
    path: []const u8,
    upstream: []const u8,
    methods: []const []const u8,
    middleware: []const []const u8,
};

/// Router for matching requests to routes
pub const Router = struct {
    allocator: std.mem.Allocator,
    routes: []const Route,

    /// Initialize a new Router
    pub fn init(allocator: std.mem.Allocator, routes: []const RouteConfig) !Router {
        // Convert config routes to our internal Route type
        var internal_routes = try allocator.alloc(Route, routes.len);
        errdefer allocator.free(internal_routes);

        for (routes, 0..) |route, i| {
            internal_routes[i] = try Route.fromConfig(allocator, route);
        }

        return Router{
            .allocator = allocator,
            .routes = internal_routes,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Router) void {
        for (self.routes) |route| {
            var mutable_route = route;
            mutable_route.deinit(self.allocator);
        }
        self.allocator.free(self.routes);
    }

    /// Find a route matching the given path and method
    pub fn findRoute(self: *Router, path: []const u8, method: []const u8) !?*const Route {
        for (self.routes) |*route| {
            if (try route.matches(path, method)) {
                return route;
            }
        }

        return null;
    }

    /// Apply middleware for a route
    pub fn applyMiddleware(self: *Router, context: *const @import("../middleware/types.zig").Context) !MiddlewareResult {
        // Find the route that matches the context
        for (self.routes) |*route| {
            if (std.mem.eql(u8, route.path_pattern, context.route.path)) {
                // Check if the route has any middleware
                if (route.middleware.len == 0) {
                    return MiddlewareResult{
                        .success = true,
                        .status_code = 200,
                        .error_message = "",
                    };
                }

                // For demonstration purposes, let's simulate middleware behavior
                // In a real implementation, we would create and apply each middleware

                // Check for JWT middleware
                for (route.middleware) |mw| {
                    if (std.mem.eql(u8, mw, "jwt")) {
                        // Check for Authorization header
                        const auth_header = context.request.headers.get("Authorization");
                        if (auth_header == null or !std.mem.startsWith(u8, auth_header.?, "Bearer ")) {
                            return MiddlewareResult{
                                .success = false,
                                .status_code = 401,
                                .error_message = "Unauthorized: Missing or invalid JWT token",
                            };
                        }
                    }
                }

                // All middleware passed
                return MiddlewareResult{
                    .success = true,
                    .status_code = 200,
                    .error_message = "",
                };
            }
        }

        // No matching route found
        return MiddlewareResult{
            .success = false,
            .status_code = 404,
            .error_message = "Not Found",
        };
    }
};

/// A route in the router
pub const Route = struct {
    path_pattern: []const u8,
    upstream_url: []const u8,
    methods: []const []const u8,
    middleware: []const []const u8,
    matcher: matcher.PathMatcher,
    upstream_pool: upstream_mod.ConnectionPool,

    /// Alias for upstream_url to maintain compatibility
    pub fn upstream(self: *const Route) []const u8 {
        return self.upstream_url;
    }

    /// Create a Route from a configuration
    pub fn fromConfig(allocator: std.mem.Allocator, config: RouteConfig) !Route {
        // Create path matcher
        var path_matcher = try matcher.PathMatcher.init(allocator, config.path);
        errdefer path_matcher.deinit();

        // Create upstream connection pool
        var pool = try upstream_mod.ConnectionPool.init(allocator, config.upstream);
        errdefer pool.deinit();

        // Copy methods
        var methods_copy = try allocator.alloc([]const u8, config.methods.len);
        errdefer allocator.free(methods_copy);

        for (config.methods, 0..) |method, i| {
            methods_copy[i] = try allocator.dupe(u8, method);
        }

        // Copy middleware
        var middleware_copy = try allocator.alloc([]const u8, config.middleware.len);
        errdefer {
            for (methods_copy) |method| {
                allocator.free(method);
            }
            allocator.free(middleware_copy);
        }

        for (config.middleware, 0..) |mw, i| {
            middleware_copy[i] = try allocator.dupe(u8, mw);
        }

        return Route{
            .path_pattern = try allocator.dupe(u8, config.path),
            .upstream_url = try allocator.dupe(u8, config.upstream),
            .methods = methods_copy,
            .middleware = middleware_copy,
            .matcher = path_matcher,
            .upstream_pool = pool,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Route, allocator: std.mem.Allocator) void {
        allocator.free(self.path_pattern);
        allocator.free(self.upstream_url);

        for (self.methods) |method| {
            allocator.free(method);
        }
        allocator.free(self.methods);

        for (self.middleware) |mw| {
            allocator.free(mw);
        }
        allocator.free(self.middleware);

        self.matcher.deinit();
        self.upstream_pool.deinit();
    }

    /// Check if this route matches the given path and method
    pub fn matches(self: *const Route, path: []const u8, method: []const u8) !bool {
        // Check if the path matches
        if (!try self.matcher.matches(path)) {
            return false;
        }

        // Check if the method is allowed
        for (self.methods) |allowed_method| {
            if (std.mem.eql(u8, method, allowed_method)) {
                return true;
            }
        }

        return false;
    }

    /// Get a connection to the upstream server
    pub fn getUpstreamConnection(self: *Route) !upstream_mod.Connection {
        return self.upstream_pool.getConnection();
    }
};

/// Result of applying middleware
pub const MiddlewareResult = struct {
    success: bool,
    status_code: u16,
    error_message: []const u8,
};

// Tests
test "Router initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Use the RouteConfig type for the test
    const TestRoute = RouteConfig;

    const routes = [_]TestRoute{
        .{
            .path = "/api/users",
            .upstream = "http://users-service:8080",
            .methods = &[_][]const u8{ "GET", "POST" },
            .middleware = &[_][]const u8{ "auth", "ratelimit" },
        },
        .{
            .path = "/api/products",
            .upstream = "http://products-service:8080",
            .methods = &[_][]const u8{"GET"},
            .middleware = &[_][]const u8{"cache"},
        },
    };

    var router = try Router.init(allocator, &routes);
    defer router.deinit();

    try testing.expectEqual(@as(usize, 2), router.routes.len);
    try testing.expectEqualStrings("/api/users", router.routes[0].path_pattern);
    try testing.expectEqualStrings("http://users-service:8080", router.routes[0].upstream_url);
    try testing.expectEqual(@as(usize, 2), router.routes[0].methods.len);
    try testing.expectEqualStrings("GET", router.routes[0].methods[0]);
    try testing.expectEqualStrings("POST", router.routes[0].methods[1]);
    try testing.expectEqual(@as(usize, 2), router.routes[0].middleware.len);
    try testing.expectEqualStrings("auth", router.routes[0].middleware[0]);
    try testing.expectEqualStrings("ratelimit", router.routes[0].middleware[1]);
}
