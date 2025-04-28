const std = @import("std");
const logger = @import("../utils/logger.zig");
const Connection = @import("connection.zig").Connection;
const Server = @import("server.zig").Server;

/// Worker thread context
pub const WorkerContext = struct {
    server: *Server,
    thread_id: usize,
};

/// Worker thread function
pub fn workerThread(context: *WorkerContext) !void {
    const server = context.server;
    const thread_id = context.thread_id;
    
    logger.debug("Worker thread {d} started", .{thread_id});
    
    while (!server.shutdown_requested.load(.Acquire)) {
        // Wait for a connection
        server.connection_semaphore.wait();
        
        // Check if shutdown was requested
        if (server.shutdown_requested.load(.Acquire)) {
            break;
        }
        
        // Get a connection from the queue
        server.queue_mutex.lock();
        const connection_opt = server.connection_queue.readItem();
        server.queue_mutex.unlock();
        
        if (connection_opt) |conn| {
            // Handle the connection
            var connection = Connection{
                .stream = conn.stream,
                .client_addr = conn.address,
                .server = server,
            };
            
            connection.handle() catch |err| {
                logger.err("Error handling connection: {}", .{err});
            };
        }
    }
    
    logger.debug("Worker thread {d} shutting down", .{thread_id});
}
