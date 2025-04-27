const std = @import("std");
const gateway = @import("gateway");

/// Custom middleware that routes traffic based on the authentication scheme
pub const AuthSchemeRouter = struct {
    // Base middleware interface
    base: gateway.middleware.types.Middleware,

    // Middleware-specific fields
    allocator: std.mem.Allocator,
    route_map: std.StringHashMap([]const u8),
    default_upstream: []const u8,

    // Create a new auth scheme router middleware
    pub fn create(allocator: std.mem.Allocator, config: anytype) !*gateway.middleware.types.Middleware {
        // Allocate memory for the middleware
        var self = try allocator.create(AuthSchemeRouter);

        // Initialize the route map
        var route_map = std.StringHashMap([]const u8).init(allocator);

        // Add routes from config
        if (@hasField(@TypeOf(config), "routes")) {
            for (config.routes) |route| {
                const scheme = try allocator.dupe(u8, route.scheme);
                const upstream = try allocator.dupe(u8, route.upstream);
                try route_map.put(scheme, upstream);
            }
        }

        // Get default upstream or use a fallback
        const default_upstream = if (@hasField(@TypeOf(config), "default_upstream"))
            try allocator.dupe(u8, config.default_upstream)
        else
            try allocator.dupe(u8, "http://localhost:3000");

        // Initialize the middleware
        self.* = AuthSchemeRouter{
            .base = gateway.middleware.types.Middleware{
                .processFn = process,
                .deinitFn = deinit,
            },
            .allocator = allocator,
            .route_map = route_map,
            .default_upstream = default_upstream,
        };

        return &self.base;
    }

    // Process a request through this middleware
    fn process(base: *gateway.middleware.types.Middleware, context: *gateway.middleware.types.Context) !gateway.middleware.types.MiddlewareResult {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(AuthSchemeRouter, "base", base);

        // Get the Authorization header
        const auth_header = context.request.headers.get("Authorization");

        // Extract the auth scheme if the header exists
        var auth_scheme: []const u8 = "none";
        if (auth_header) |header| {
            const space_index = std.mem.indexOf(u8, header, " ");
            if (space_index) |index| {
                auth_scheme = header[0..index];
            }
        }

        // Log the auth scheme
        const logger = std.log.scoped(.auth_scheme_router);
        logger.info("Auth scheme: {s}", .{auth_scheme});

        // Look up the upstream URL for this auth scheme
        var upstream_url: []const u8 = undefined;
        if (self.route_map.get(auth_scheme)) |url| {
            upstream_url = url;
            logger.info("Routing to {s} based on auth scheme", .{upstream_url});
        } else {
            upstream_url = self.default_upstream;
            logger.info("Using default upstream {s}", .{upstream_url});
        }

        // Modify the route's upstream URL
        // Note: We need to allocate a new string since we don't own the original
        const new_upstream = try self.allocator.dupe(u8, upstream_url);

        // Create a mutable copy of the route
        var mutable_route = context.route.*;
        mutable_route.upstream = new_upstream;

        // Update the context with the new route
        context.route.* = mutable_route;

        // Allow the request to continue
        return gateway.middleware.types.MiddlewareResult{
            .success = true,
            .status_code = 200,
            .error_message = "",
        };
    }

    // Clean up resources
    fn deinit(base: *gateway.middleware.types.Middleware) void {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(AuthSchemeRouter, "base", base);

        // Free memory for route map entries
        var it = self.route_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.route_map.deinit();

        // Free the default upstream
        self.allocator.free(self.default_upstream);

        // Free the middleware itself
        self.allocator.destroy(self);
    }
};

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize middleware system
    try gateway.middleware.registry.initGlobalRegistry(allocator);
    defer gateway.middleware.registry.deinitGlobalRegistry();

    // Register custom middleware
    try gateway.middleware.registry.register("auth-scheme-router", AuthSchemeRouter.create);

    // Create configuration
    var config = try gateway.config.Config.init(allocator);
    defer config.deinit();

    // Configure listen address and port
    allocator.free(config.listen_address);
    config.listen_address = try allocator.dupe(u8, "127.0.0.1");
    config.listen_port = 8080;

    // Add a single route with the auth scheme router middleware
    var routes = try allocator.alloc(gateway.config.Route, 1);

    // API route with auth scheme router middleware
    routes[0] = try gateway.config.Route.init(
        allocator,
        "/api",
        "http://default-service:8080", // This will be overridden by the middleware
        &[_][]const u8{ "GET", "POST" },
        &[_][]const u8{"auth-scheme-router"}, // Use our custom middleware
    );

    config.routes = routes;

    // Initialize and run the gateway
    var gw = try gateway.Gateway.init(allocator, config);
    defer gw.deinit();

    // Configure the auth scheme router middleware
    const auth_routes = [_]struct { scheme: []const u8, upstream: []const u8 }{
        .{ .scheme = "Bearer", .upstream = "https://www.google.com" },
        .{ .scheme = "ServiceKey", .upstream = "https://www.duckduckgo.com" },
        .{ .scheme = "ApiKey", .upstream = "https://www.bing.com" },
    };

    // Create middleware configuration
    const middleware_config = .{
        .routes = &auth_routes,
        .default_upstream = "https://www.example.com",
    };

    // Create and configure the middleware
    var middleware = try AuthSchemeRouter.create(allocator, middleware_config);
    defer middleware.deinit();

    std.debug.print("Starting ZProxy with auth scheme router middleware on port {d}...\n", .{config.listen_port});
    std.debug.print("Try these requests:\n", .{});
    std.debug.print("  curl -H \"Authorization: Bearer token\" http://localhost:8080/api\n", .{});
    std.debug.print("  curl -H \"Authorization: ServiceKey token\" http://localhost:8080/api\n", .{});
    std.debug.print("  curl -H \"Authorization: ApiKey token\" http://localhost:8080/api\n", .{});
    std.debug.print("  curl http://localhost:8080/api\n", .{});

    try gw.run();
}
