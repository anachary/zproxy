const std = @import("std");
const config = @import("../config/config.zig");
const logger = @import("../utils/logger.zig");
const route = @import("route.zig");
const matcher = @import("matcher.zig");

pub const RouteParam = route.RouteParam;
pub const RouteMatch = route.RouteMatch;

/// Router for matching paths to routes
pub const Router = struct {
    allocator: std.mem.Allocator,
    routes: []config.Route,

    /// Initialize the router
    pub fn init(allocator: std.mem.Allocator, routes: []config.Route) !Router {
        return Router{
            .allocator = allocator,
            .routes = routes,
        };
    }

    /// Clean up router resources
    pub fn deinit(self: *Router) void {
        _ = self;
        // Routes are owned by the config, so we don't free them here
    }

    /// Find a route that matches the given path and method
    pub fn findRoute(self: *Router, path: []const u8, method: []const u8) ?*const config.Route {
        logger.debug("Finding route for {s} {s}", .{ method, path });

        for (self.routes) |*route_config| {
            // Check if the route matches the path
            if (matcher.matchPath(route_config.path, path)) {
                // Check if the route allows the method
                for (route_config.methods) |allowed_method| {
                    if (std.mem.eql(u8, allowed_method, method)) {
                        logger.debug("Found route: {s} -> {s}", .{ route_config.path, route_config.upstream });
                        return route_config;
                    }
                }

                // Route matches path but not method
                logger.debug("Route {s} doesn't allow method {s}", .{ route_config.path, method });
                return null;
            }
        }

        // No matching route found
        logger.debug("No route found for {s} {s}", .{ method, path });
        return null;
    }

    /// Find a route with parameter extraction
    pub fn findRouteWithParams(self: *Router, path: []const u8, method: []const u8) !?RouteMatch {
        logger.debug("Finding route with params for {s} {s}", .{ method, path });

        for (self.routes) |*route_config| {
            // Check if the route matches the path and extract parameters
            if (try matcher.matchPathWithParams(self.allocator, route_config.path, path)) |params| {
                // Check if the route allows the method
                for (route_config.methods) |allowed_method| {
                    if (std.mem.eql(u8, allowed_method, method)) {
                        logger.debug("Found route with params: {s} -> {s}", .{ route_config.path, route_config.upstream });
                        return RouteMatch{
                            .route = route_config,
                            .params = params,
                        };
                    }
                }

                // Route matches path but not method
                logger.debug("Route {s} doesn't allow method {s}", .{ route_config.path, method });

                // Free parameters
                for (params) |param| {
                    self.allocator.free(param.name);
                    self.allocator.free(param.value);
                }
                self.allocator.free(params);

                return null;
            }
        }

        // No matching route found
        logger.debug("No route found for {s} {s}", .{ method, path });
        return null;
    }

    // Path matching is now in matcher.zig
};

test "Router - Exact Match" {
    const testing = std.testing;

    // Create test routes
    var routes = [_]config.Route{
        .{
            .path = "/api/users",
            .upstream = "http://users-service",
            .methods = &[_][]const u8{ "GET", "POST" },
        },
        .{
            .path = "/api/products",
            .upstream = "http://products-service",
            .methods = &[_][]const u8{"GET"},
        },
    };

    // Create router
    var router = try Router.init(testing.allocator, &routes);
    defer router.deinit();

    // Test exact matches
    const route1 = router.findRoute("/api/users", "GET");
    try testing.expect(route1 != null);
    try testing.expectEqualStrings("/api/users", route1.?.path);
    try testing.expectEqualStrings("http://users-service", route1.?.upstream);

    const route2 = router.findRoute("/api/products", "GET");
    try testing.expect(route2 != null);
    try testing.expectEqualStrings("/api/products", route2.?.path);
    try testing.expectEqualStrings("http://products-service", route2.?.upstream);

    // Test method not allowed
    const route3 = router.findRoute("/api/products", "POST");
    try testing.expect(route3 == null);

    // Test path not found
    const route4 = router.findRoute("/api/orders", "GET");
    try testing.expect(route4 == null);
}

test "Router - Wildcard Match" {
    const testing = std.testing;

    // Create test routes
    var routes = [_]config.Route{
        .{
            .path = "/api/*",
            .upstream = "http://api-gateway",
            .methods = &[_][]const u8{ "GET", "POST" },
        },
    };

    // Create router
    var router = try Router.init(testing.allocator, &routes);
    defer router.deinit();

    // Test wildcard matches
    const route1 = router.findRoute("/api/users", "GET");
    try testing.expect(route1 != null);
    try testing.expectEqualStrings("/api/*", route1.?.path);
    try testing.expectEqualStrings("http://api-gateway", route1.?.upstream);

    const route2 = router.findRoute("/api/products/123", "POST");
    try testing.expect(route2 != null);
    try testing.expectEqualStrings("/api/*", route2.?.path);
    try testing.expectEqualStrings("http://api-gateway", route2.?.upstream);

    // Test non-matching path
    const route3 = router.findRoute("/web/index.html", "GET");
    try testing.expect(route3 == null);
}

test "Router - Parameter Match" {
    const testing = std.testing;

    // Create test routes
    var routes = [_]config.Route{
        .{
            .path = "/api/users/:id",
            .upstream = "http://users-service",
            .methods = &[_][]const u8{"GET"},
        },
    };

    // Create router
    var router = try Router.init(testing.allocator, &routes);
    defer router.deinit();

    // Test parameter match
    const route1 = router.findRoute("/api/users/123", "GET");
    try testing.expect(route1 != null);
    try testing.expectEqualStrings("/api/users/:id", route1.?.path);
    try testing.expectEqualStrings("http://users-service", route1.?.upstream);

    // Test parameter extraction
    const match = try router.findRouteWithParams("/api/users/123", "GET");
    try testing.expect(match != null);
    defer match.?.deinit(testing.allocator);

    try testing.expectEqualStrings("/api/users/:id", match.?.route.path);
    try testing.expectEqualStrings("http://users-service", match.?.route.upstream);
    try testing.expectEqual(@as(usize, 1), match.?.params.len);
    try testing.expectEqualStrings("id", match.?.params[0].name);
    try testing.expectEqualStrings("123", match.?.params[0].value);
}
