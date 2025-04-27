const std = @import("std");
const gateway_optimized = @import("gateway_optimized.zig");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    const logger = std.log.scoped(.main);
    logger.info("Starting optimized gateway...", .{});

    // Load configuration
    var config = try gateway_optimized.config.Config.loadFromFile(allocator, "config.json");
    defer config.deinit();

    // Initialize and run the optimized gateway
    var gw = try gateway_optimized.Gateway.init(allocator, config);
    defer gw.deinit();

    try gw.run();

    logger.info("Gateway shutdown complete", .{});
}
