const std = @import("std");
const config = @import("../config/config.zig");
const logger = @import("../utils/logger.zig");
const router = @import("../router/router.zig");
const middleware = @import("../middleware/middleware.zig");
const thread_pool = @import("thread_pool.zig");

// Connection handling is now in connection.zig

// HTTP request parsing is now in protocol/http1.zig
// Worker thread handling is now in thread_pool.zig

/// Main server structure
pub const Server = struct {
    allocator: std.mem.Allocator,
    config: config.Config,
    stream_server: std.net.StreamServer,
    router: router.Router,
    middleware: middleware.MiddlewareChain,

    // Thread management
    worker_threads: []std.Thread,
    worker_contexts: []thread_pool.WorkerContext,

    // Connection queue
    connection_queue: std.fifo.LinearFifo(std.net.StreamServer.Connection, .Dynamic),
    queue_mutex: std.Thread.Mutex,
    connection_semaphore: std.Thread.Semaphore,

    // Shutdown flag
    shutdown_requested: std.atomic.Atomic(bool),

    /// Initialize the server
    pub fn init(allocator: std.mem.Allocator, server_config: config.Config) !Server {
        // Create server options
        const server_options = std.net.StreamServer.Options{
            .reuse_address = true,
            .reuse_port = false,
            .kernel_backlog = server_config.backlog,
        };

        // Create stream server
        var stream_server = std.net.StreamServer.init(server_options);

        // Create router
        var route_router = try router.Router.init(allocator, server_config.routes);

        // Create middleware chain
        var mw_chain = try middleware.MiddlewareChain.init(allocator);

        // Create connection queue
        var conn_queue = std.fifo.LinearFifo(std.net.StreamServer.Connection, .Dynamic).init(allocator);

        // Create worker threads and contexts
        var threads = try allocator.alloc(std.Thread, server_config.thread_count);
        var contexts = try allocator.alloc(thread_pool.WorkerContext, server_config.thread_count);

        return Server{
            .allocator = allocator,
            .config = server_config,
            .stream_server = stream_server,
            .router = route_router,
            .middleware = mw_chain,
            .worker_threads = threads,
            .worker_contexts = contexts,
            .connection_queue = conn_queue,
            .queue_mutex = std.Thread.Mutex{},
            .connection_semaphore = std.Thread.Semaphore{},
            .shutdown_requested = std.atomic.Atomic(bool).init(false),
        };
    }

    /// Start the server
    pub fn start(self: *Server) !void {
        logger.info("Starting server on {s}:{d}", .{ self.config.host, self.config.port });

        // Bind to address
        const address = try std.net.Address.parseIp(self.config.host, self.config.port);
        try self.stream_server.listen(address);

        // Start worker threads
        for (0..self.config.thread_count) |i| {
            self.worker_contexts[i] = thread_pool.WorkerContext{
                .server = self,
                .thread_id = i,
            };

            self.worker_threads[i] = try std.Thread.spawn(.{}, thread_pool.workerThread, .{&self.worker_contexts[i]});
        }

        logger.info("Server started with {d} worker threads", .{self.config.thread_count});

        // Accept connections
        while (!self.shutdown_requested.load(.Acquire)) {
            const connection = self.stream_server.accept() catch |err| {
                if (err == error.ConnectionAborted or
                    err == error.ConnectionResetByPeer or
                    err == error.WouldBlock)
                {
                    // These are common errors, just continue
                    continue;
                }

                logger.err("Error accepting connection: {}", .{err});
                continue;
            };

            logger.debug("Accepted connection from {}", .{connection.address});

            // Add connection to the queue
            self.queue_mutex.lock();
            self.connection_queue.writeItem(connection) catch {
                logger.err("Error adding connection to queue", .{});
                connection.stream.close();
                self.queue_mutex.unlock();
                continue;
            };
            self.queue_mutex.unlock();

            // Signal a worker thread
            self.connection_semaphore.post();
        }
    }

    /// Stop the server
    pub fn stop(self: *Server) !void {
        logger.info("Stopping server...", .{});

        // Set shutdown flag
        self.shutdown_requested.store(true, .Release);

        // Close the server
        self.stream_server.close();

        // Signal all worker threads to exit
        for (0..self.config.thread_count) |_| {
            self.connection_semaphore.post();
        }

        // Wait for all worker threads to exit
        for (self.worker_threads) |thread| {
            thread.join();
        }

        logger.info("Server stopped", .{});
    }

    /// Clean up server resources
    pub fn deinit(self: *Server) void {
        // Free worker threads and contexts
        self.allocator.free(self.worker_threads);
        self.allocator.free(self.worker_contexts);

        // Deinitialize connection queue
        self.connection_queue.deinit();

        // Deinitialize router and middleware
        self.router.deinit();
        self.middleware.deinit();

        // Deinitialize stream server
        self.stream_server.deinit();
    }
};

test "Server - Initialization" {
    const testing = std.testing;

    // Create a test configuration
    var test_config = config.getDefaultConfig(testing.allocator);
    defer test_config.deinit();

    // Initialize the server
    var server = try Server.init(testing.allocator, test_config);
    defer server.deinit();

    // Check that the server was initialized correctly
    try testing.expectEqual(test_config.port, server.config.port);
    try testing.expectEqualStrings(test_config.host, server.config.host);
    try testing.expectEqual(test_config.thread_count, server.config.thread_count);
    try testing.expectEqual(@as(usize, 0), server.connection_queue.readableLength());
    try testing.expectEqual(false, server.shutdown_requested.load(.Acquire));
}
