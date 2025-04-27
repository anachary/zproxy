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
    
    // Add a route
    const route = try gateway.config.Route.init(
        allocator,
        "/api",
        "http://localhost:3000",
        &[_][]const u8{ "GET", "POST", "PUT", "DELETE" },
        &[_][]const u8{},
    );
    
    config.routes = try allocator.alloc(gateway.config.Route, 1);
    config.routes[0] = route;
    
    // Initialize and run the gateway
    var gw = try gateway.Gateway.init(allocator, config);
    defer gw.deinit();
    
    std.debug.print("Starting gateway on {s}:{d}\n", .{
        config.listen_address,
        config.listen_port,
    });
    
    try gw.run();
}
