const std = @import("std");
const gateway = @import("gateway");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create configuration
    var config = try gateway.config.Config.init(allocator);
    defer config.deinit();
    
    // Configure listen address and port
    allocator.free(config.listen_address);
    config.listen_address = try allocator.dupe(u8, "0.0.0.0");
    config.listen_port = 8080;
    
    // Configure middleware
    config.middleware.rate_limit.enabled = true;
    config.middleware.rate_limit.requests_per_minute = 100;
    
    config.middleware.auth.enabled = true;
    config.middleware.auth.jwt_secret = try allocator.dupe(u8, "your-secret-key");
    
    config.middleware.cache.enabled = true;
    config.middleware.cache.ttl_seconds = 300;
    
    // Add routes
    var routes = try allocator.alloc(gateway.config.Route, 3);
    
    // Users API route with authentication
    routes[0] = try gateway.config.Route.init(
        allocator,
        "/api/users",
        "http://users-service:8080",
        &[_][]const u8{ "GET", "POST", "PUT", "DELETE" },
        &[_][]const u8{ "jwt", "ratelimit" },
    );
    
    // Products API route with caching
    routes[1] = try gateway.config.Route.init(
        allocator,
        "/api/products",
        "http://products-service:8080",
        &[_][]const u8{ "GET" },
        &[_][]const u8{ "cache" },
    );
    
    // Public API route
    routes[2] = try gateway.config.Route.init(
        allocator,
        "/api/public",
        "http://public-service:8080",
        &[_][]const u8{ "GET" },
        &[_][]const u8{},
    );
    
    config.routes = routes;
    
    // Initialize and run the gateway
    var gw = try gateway.Gateway.init(allocator, config);
    defer gw.deinit();
    
    std.debug.print("Starting gateway on {s}:{d}\n", .{
        config.listen_address,
        config.listen_port,
    });
    
    try gw.run();
}
