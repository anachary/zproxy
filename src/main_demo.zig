const std = @import("std");
const logger = @import("utils/logger_simple.zig");

pub fn main() !void {
    // Initialize logger
    logger.init(.info);
    defer logger.deinit();
    
    // Log startup message
    logger.info("ZProxy starting up...", .{});
    
    // Print configuration
    const config = struct {
        host: []const u8 = "0.0.0.0",
        port: u16 = 8000,
        thread_count: u32 = 4,
        protocols: []const []const u8 = &[_][]const u8{ "http1", "http2", "websocket" },
    }{};
    
    logger.info("Configuration:", .{});
    logger.info("  Host: {s}", .{config.host});
    logger.info("  Port: {d}", .{config.port});
    logger.info("  Thread count: {d}", .{config.thread_count});
    logger.info("  Protocols:", .{});
    for (config.protocols) |protocol| {
        logger.info("    - {s}", .{protocol});
    }
    
    // Simulate server startup
    logger.info("Server starting...", .{});
    std.time.sleep(1 * std.time.ns_per_s);
    logger.info("Server started successfully", .{});
    logger.info("Listening on {s}:{d}", .{config.host, config.port});
    
    // Simulate handling a request
    logger.info("Received request: GET /api/users", .{});
    std.time.sleep(500 * std.time.ns_per_ms);
    logger.info("Request processed successfully", .{});
    
    // Simulate server shutdown
    logger.info("Server shutting down...", .{});
    std.time.sleep(500 * std.time.ns_per_ms);
    logger.info("Server shutdown complete", .{});
}
