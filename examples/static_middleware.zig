const std = @import("std");
const gateway = @import("gateway");

/// Simple logging middleware that logs requests
const LoggingMiddleware = struct {
    prefix: []const u8,
    allocator: std.mem.Allocator,

    /// Initialize the middleware
    pub fn init(allocator: std.mem.Allocator, config: struct { prefix: []const u8 }) !@This() {
        return .{
            .allocator = allocator,
            .prefix = try allocator.dupe(u8, config.prefix),
        };
    }

    /// Process a request
    pub fn process(self: *const @This(), context: *gateway.middleware.types.Context) !gateway.middleware.types.MiddlewareResult {
        // Log the request
        std.log.info("[{s}] Request: {s} {s}", .{
            self.prefix,
            context.request.method,
            context.request.path,
        });

        // Allow the request to continue
        return gateway.middleware.types.MiddlewareResult{
            .success = true,
            .status_code = 200,
            .error_message = "",
        };
    }

    /// Clean up resources
    pub fn deinit(self: *const @This()) void {
        self.allocator.free(self.prefix);
    }
};

/// Simple example of using a static middleware chain
pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define our middleware chain at compile time
    const MyChain = gateway.middleware.chain.StaticChain(.{LoggingMiddleware});

    // Create configuration for the middleware
    const configs = .{.{ .prefix = "ZPROXY" }};

    // Initialize the middleware chain
    var chain = try MyChain.init(allocator, configs);
    defer chain.deinit();

    // Create configuration for the gateway
    var config = try gateway.config.Config.init(allocator);
    defer config.deinit();

    // Configure listen address and port
    allocator.free(config.listen_address);
    config.listen_address = try allocator.dupe(u8, "127.0.0.1");
    config.listen_port = 8080;

    // Add routes
    var routes = try allocator.alloc(gateway.config.Route, 2);

    // API route
    routes[0] = try gateway.config.Route.init(
        allocator,
        "/api",
        "http://localhost:3000",
        &[_][]const u8{ "GET", "POST" },
        &[_][]const u8{}, // No middleware names needed since we're using a static chain
    );

    // Users route
    routes[1] = try gateway.config.Route.init(
        allocator,
        "/users",
        "http://localhost:3001",
        &[_][]const u8{ "GET", "POST" },
        &[_][]const u8{}, // No middleware names needed since we're using a static chain
    );

    config.routes = routes;

    // Initialize and run the gateway
    var gw = try gateway.Gateway.init(allocator, config);
    defer gw.deinit();

    std.debug.print("Starting ZProxy with static middleware chain on port {d}...\n", .{config.listen_port});
    std.debug.print("The LoggingMiddleware will log all requests.\n", .{});
    std.debug.print("Try these requests:\n", .{});
    std.debug.print("  curl http://localhost:8080/api\n", .{});
    std.debug.print("  curl http://localhost:8080/users\n", .{});

    try gw.run();
}
