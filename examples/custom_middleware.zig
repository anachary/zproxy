const std = @import("std");
const gateway = @import("gateway");

/// Custom logging middleware
pub const LoggingMiddleware = struct {
    // Base middleware interface
    base: gateway.middleware.types.Middleware,

    // Middleware-specific fields
    allocator: std.mem.Allocator,
    prefix: []const u8,

    // Create a new logging middleware
    pub fn create(allocator: std.mem.Allocator, config: anytype) !*gateway.middleware.types.Middleware {
        // Allocate memory for the middleware
        var self = try allocator.create(LoggingMiddleware);

        // Get prefix from config or use default
        const prefix = if (@hasField(@TypeOf(config), "prefix"))
            try allocator.dupe(u8, config.prefix)
        else
            try allocator.dupe(u8, "LOG");

        // Initialize the middleware
        self.* = LoggingMiddleware{
            .base = gateway.middleware.types.Middleware{
                .processFn = process,
                .deinitFn = deinit,
            },
            .allocator = allocator,
            .prefix = prefix,
        };

        return &self.base;
    }

    // Process a request through this middleware
    fn process(base: *gateway.middleware.types.Middleware, context: *gateway.middleware.types.Context) !gateway.middleware.types.MiddlewareResult {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(LoggingMiddleware, "base", base);

        // Log the request
        const logger = std.log.scoped(.logging_middleware);
        logger.info("[{s}] Request: {s} {s}", .{ self.prefix, context.request.method, context.request.path });

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
        const self = @fieldParentPtr(LoggingMiddleware, "base", base);

        // Free memory
        self.allocator.free(self.prefix);
        self.allocator.destroy(self);
    }
};

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize middleware system
    const registry = gateway.middleware.registry;
    try registry.initGlobalRegistry(allocator);
    defer registry.deinitGlobalRegistry();

    // Register custom middleware
    try registry.register("logging", LoggingMiddleware.create);

    // Create configuration
    var config = try gateway.config.Config.init(allocator);
    defer config.deinit();

    // Configure listen address and port
    allocator.free(config.listen_address);
    config.listen_address = try allocator.dupe(u8, "127.0.0.1");
    config.listen_port = 8080;

    // Add routes
    var routes = try allocator.alloc(gateway.config.Route, 2);

    // Public API route with logging middleware
    routes[0] = try gateway.config.Route.init(
        allocator,
        "/api/public",
        "http://localhost:3000",
        &[_][]const u8{"GET"},
        &[_][]const u8{"logging"}, // Use our custom middleware
    );

    // Protected API route with logging and JWT middleware
    routes[1] = try gateway.config.Route.init(
        allocator,
        "/api/users",
        "http://localhost:3001",
        &[_][]const u8{ "GET", "POST" },
        &[_][]const u8{ "logging", "jwt" }, // Use both middlewares
    );

    config.routes = routes;

    // Initialize and run the gateway
    var gw = try gateway.Gateway.init(allocator, config);
    defer gw.deinit();

    std.debug.print("Starting ZProxy with custom middleware on port {d}...\n", .{config.listen_port});
    try gw.run();
}
