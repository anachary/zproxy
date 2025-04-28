const std = @import("std");
const config = @import("config/config.zig");
const config_loader = @import("config/loader.zig");
const server = @import("server/server.zig");
const logger = @import("utils/logger.zig");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    try logger.init(allocator);
    defer logger.deinit();

    logger.info("Starting ZProxy - The fastest proxy ever", .{});

    // Parse command line arguments
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Load configuration
    var server_config: config.Config = undefined;
    if (args.len > 1) {
        // Load configuration from file
        server_config = try config_loader.loadFromFile(allocator, args[1]);
    } else {
        // Use default configuration
        server_config = config.getDefaultConfig(allocator);
    }
    defer server_config.deinit();

    logger.info("Configuration loaded: {s}:{d}", .{ server_config.host, server_config.port });

    // Create and start the server
    var proxy_server = try server.Server.init(allocator, server_config);
    defer proxy_server.deinit();

    try proxy_server.start();

    // Wait for termination signal
    const signal = try waitForSignal();
    logger.info("Received signal: {}, shutting down...", .{signal});

    // Graceful shutdown
    try proxy_server.stop();
    logger.info("ZProxy shutdown complete", .{});
}

fn waitForSignal() !u32 {
    // Create a simple way to wait for Ctrl+C
    logger.info("Press Ctrl+C to stop the server", .{});

    // For now, just wait for user input
    const stdin = std.io.getStdIn().reader();
    _ = try stdin.readByte();

    return 2; // SIGINT
}

// Export test functions
test {
    // Run all tests in the project
    std.testing.refAllDeclsRecursive(@This());
    _ = @import("config/config.zig");
    _ = @import("config/loader.zig");
    _ = @import("server/server.zig");
    _ = @import("server/connection.zig");
    _ = @import("server/thread_pool.zig");
    _ = @import("protocol/detector.zig");
    _ = @import("protocol/http1.zig");
    _ = @import("protocol/http2.zig");
    _ = @import("protocol/websocket.zig");
    _ = @import("router/router.zig");
    _ = @import("router/matcher.zig");
    _ = @import("router/route.zig");
    _ = @import("proxy/proxy.zig");
    _ = @import("proxy/upstream.zig");
    _ = @import("proxy/pool.zig");
    _ = @import("middleware/middleware.zig");
    _ = @import("middleware/auth.zig");
    _ = @import("middleware/rate_limit.zig");
    _ = @import("middleware/cors.zig");
    _ = @import("middleware/cache.zig");
    _ = @import("tls/tls.zig");
    _ = @import("tls/certificate.zig");
    _ = @import("utils/logger.zig");
    _ = @import("utils/buffer.zig");
    _ = @import("utils/allocator.zig");
    _ = @import("utils/numa.zig");
}
