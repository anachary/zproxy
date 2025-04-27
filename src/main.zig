const std = @import("std");
const gateway = @import("gateway.zig");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    const logger = std.log.scoped(.main);
    logger.info("Starting gateway...", .{});

    // Load configuration
    var config = try gateway.config.Config.loadFromFile(allocator, "config.json");
    defer config.deinit();

    // Initialize and run the gateway
    var gw = try gateway.Gateway.init(allocator, config);
    defer gw.deinit();

    try gw.run();
    
    logger.info("Gateway shutdown complete", .{});
}
