const std = @import("std");

// Re-export modules
pub const config = @import("config/config.zig");
pub const protocol = @import("protocol/detector.zig");
pub const router = @import("router/router.zig");
pub const middleware = @import("middleware/middleware.zig");
pub const tls = @import("tls/manager.zig");
pub const metrics = @import("metrics/collector.zig");
pub const utils = @import("utils/allocator.zig");

// Import optimized components
const thread_pool_mod = @import("utils/thread_pool.zig");
const numa_mod = @import("utils/numa.zig");
const acceptor_mod = @import("utils/acceptor.zig");
const vectored_io_mod = @import("utils/vectored_io.zig");

/// Buffer pool for efficient memory reuse
pub const ConnectionBufferPool = struct {
    buffer_pool: utils.buffer.BufferPool,

    /// Initialize a new connection buffer pool
    pub fn init(allocator: std.mem.Allocator) !ConnectionBufferPool {
        return ConnectionBufferPool{
            .buffer_pool = utils.buffer.BufferPool.init(allocator, 16384, 1000),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *ConnectionBufferPool) void {
        self.buffer_pool.deinit();
    }

    /// Get a buffer from the pool
    pub fn getBuffer(self: *ConnectionBufferPool) ![]u8 {
        return self.buffer_pool.getBuffer();
    }

    /// Return a buffer to the pool
    pub fn returnBuffer(self: *ConnectionBufferPool, buffer: []u8) void {
        self.buffer_pool.returnBuffer(buffer);
    }
};

/// The Gateway is the main entry point for the API gateway.
/// It handles incoming connections, protocol detection, routing,
/// and proxying requests to upstream services.
pub const Gateway = struct {
    allocator: std.mem.Allocator,
    config: config.Config,
    router: router.Router,
    tls_manager: tls.Manager,
    metrics_collector: metrics.Collector,
    server: ?std.net.StreamServer = null,
    shutdown_requested: std.atomic.Atomic(bool),
    thread_pool: ThreadPool,
    buffer_pool: ConnectionBufferPool,

    /// Connection handler context
    const ConnectionHandlerContext = struct {
        gateway: *Gateway,
        connection: std.net.StreamServer.Connection,
    };

    /// Initialize a new Gateway instance
    pub fn init(allocator: std.mem.Allocator, cfg: config.Config) !Gateway {
        // Convert config routes to router routes
        var router_routes = try allocator.alloc(router.RouteConfig, cfg.routes.len);
        defer allocator.free(router_routes);

        for (cfg.routes, 0..) |route, i| {
            router_routes[i] = router.RouteConfig{
                .path = route.path,
                .upstream = route.upstream,
                .methods = route.methods,
                .middleware = route.middleware,
            };
        }

        var router_instance = try router.Router.init(allocator, router_routes);
        var tls_manager_instance = try tls.Manager.init(allocator, cfg.tls);
        var metrics_collector_instance = try metrics.Collector.init(allocator);

        // Determine optimal thread count (use number of CPU cores)
        const thread_count = try std.Thread.getCpuCount();
        var thread_pool = try ThreadPool.init(allocator, thread_count);
        errdefer thread_pool.deinit();

        var buffer_pool = try ConnectionBufferPool.init(allocator);
        errdefer buffer_pool.deinit();

        return Gateway{
            .allocator = allocator,
            .config = cfg,
            .router = router_instance,
            .tls_manager = tls_manager_instance,
            .metrics_collector = metrics_collector_instance,
            .shutdown_requested = std.atomic.Atomic(bool).init(false),
            .thread_pool = thread_pool,
            .buffer_pool = buffer_pool,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Gateway) void {
        if (self.server) |*server| {
            server.deinit();
        }
        self.thread_pool.deinit();
        self.buffer_pool.deinit();
        self.router.deinit();
        self.tls_manager.deinit();
        self.metrics_collector.deinit();
    }

    /// Start the gateway and begin accepting connections
    pub fn run(self: *Gateway) !void {
        const logger = std.log.scoped(.gateway);
        logger.info("Starting gateway on {s}:{d} with {d} worker threads", .{
            self.config.listen_address,
            self.config.listen_port,
            self.thread_pool.threads.len,
        });

        // Create server with optimized options
        const server_options = std.net.StreamServer.Options{
            .reuse_address = true,
            .reuse_port = true,
            .kernel_backlog = 1024,
        };

        const address = try std.net.Address.parseIp(
            self.config.listen_address,
            self.config.listen_port,
        );
        self.server = std.net.StreamServer.init(server_options);
        try self.server.?.listen(address);

        // Accept connections until shutdown is requested
        while (!self.shutdown_requested.load(.Acquire)) {
            const connection = self.server.?.accept() catch |err| {
                if (err == error.ConnectionAborted or
                    err == error.ConnectionResetByPeer)
                {
                    // These are common errors, just continue
                    continue;
                }
                return err;
            };

            // Create connection handler context
            var context = try self.allocator.create(ConnectionHandlerContext);
            context.* = ConnectionHandlerContext{
                .gateway = self,
                .connection = connection,
            };

            // Add connection handling job to thread pool
            try self.thread_pool.addJob(connectionHandlerJob, @ptrCast(context));
        }
    }

    /// Request a graceful shutdown of the gateway
    pub fn shutdown(self: *Gateway) void {
        self.shutdown_requested.store(true, .Release);
        if (self.server) |*server| {
            server.close();
        }
    }

    /// Connection handler job function for thread pool
    fn connectionHandlerJob(context_ptr: *anyopaque) void {
        const context = @as(*ConnectionHandlerContext, @ptrCast(@alignCast(context_ptr)));
        defer context.gateway.allocator.destroy(context);

        handleConnection(context.gateway, context.connection) catch |err| {
            const logger = std.log.scoped(.connection);
            logger.err("Error handling connection: {}", .{err});
        };
    }

    /// Handle a single client connection
    fn handleConnection(self: *Gateway, connection: std.net.StreamServer.Connection) !void {
        const logger = std.log.scoped(.connection);
        logger.debug("New connection from {}", .{connection.address});

        // Get a buffer from the pool
        const buffer = try self.buffer_pool.getBuffer();
        defer self.buffer_pool.returnBuffer(buffer);

        // Set up connection context with pooled buffer
        var conn_context = try ConnectionContext.init(
            self.allocator,
            connection,
            &self.router,
            &self.metrics_collector,
            buffer,
        );
        defer conn_context.deinit();

        // Start timer for metrics
        var timer = utils.time.Timer.start();

        // Detect protocol
        const detected_protocol = try protocol.detectProtocol(&conn_context);

        // Handle the connection based on the detected protocol
        switch (detected_protocol) {
            .http1 => try protocol.http1.handle(&conn_context),
            .http2 => try protocol.http2.handle(&conn_context),
            .websocket => try protocol.websocket.handle(&conn_context),
            .unknown => {
                logger.warn("Unknown protocol, closing connection", .{});
                return;
            },
        }

        // Record metrics
        const elapsed = timer.elapsedMillis();
        try self.metrics_collector.recordHistogram("request_duration_ms", @floatFromInt(elapsed));
        try self.metrics_collector.incrementCounter("requests_total", 1);
    }
};

/// Context for a single client connection
const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    connection: std.net.StreamServer.Connection,
    router: *router.Router,
    metrics_collector: *metrics.Collector,
    buffer: []u8,
    owns_buffer: bool,
    timer: utils.time.Timer,
    zero_copy_pool: ?*utils.zero_copy.ZeroCopyBufferPool,

    pub fn init(
        allocator: std.mem.Allocator,
        connection: std.net.StreamServer.Connection,
        route_handler: *router.Router,
        metrics_collector: *metrics.Collector,
        buffer: ?[]u8,
    ) !ConnectionContext {
        // Initialize with default timer (will be reset when handling starts)
        const timer = utils.time.Timer.start();

        // Create a shared zero-copy buffer pool for this connection
        var zero_copy_pool = try allocator.create(utils.zero_copy.ZeroCopyBufferPool);
        zero_copy_pool.* = utils.zero_copy.ZeroCopyBufferPool.init(allocator, 65536, 4);

        if (buffer) |buf| {
            return ConnectionContext{
                .allocator = allocator,
                .connection = connection,
                .router = route_handler,
                .metrics_collector = metrics_collector,
                .buffer = buf,
                .owns_buffer = false,
                .timer = timer,
                .zero_copy_pool = zero_copy_pool,
            };
        } else {
            const new_buffer = try allocator.alloc(u8, 16384);
            return ConnectionContext{
                .allocator = allocator,
                .connection = connection,
                .router = route_handler,
                .metrics_collector = metrics_collector,
                .buffer = new_buffer,
                .owns_buffer = true,
                .timer = timer,
                .zero_copy_pool = zero_copy_pool,
            };
        }
    }

    pub fn deinit(self: *ConnectionContext) void {
        if (self.owns_buffer) {
            self.allocator.free(self.buffer);
        }

        // Clean up zero-copy buffer pool
        if (self.zero_copy_pool) |pool| {
            pool.deinit();
            self.allocator.destroy(pool);
        }

        self.connection.stream.close();
    }

    /// Get a zero-copy buffer from the pool
    pub fn getZeroCopyBuffer(self: *ConnectionContext) !*utils.zero_copy.ZeroCopyBuffer {
        if (self.zero_copy_pool) |pool| {
            return pool.getBuffer();
        }

        // Fallback to creating a new buffer if no pool is available
        var buffer = try self.allocator.create(utils.zero_copy.ZeroCopyBuffer);
        buffer.* = try utils.zero_copy.ZeroCopyBuffer.init(self.allocator, 65536);
        return buffer;
    }

    /// Return a zero-copy buffer to the pool
    pub fn returnZeroCopyBuffer(self: *ConnectionContext, buffer: *utils.zero_copy.ZeroCopyBuffer) void {
        if (self.zero_copy_pool) |pool| {
            pool.returnBuffer(buffer);
        } else {
            buffer.deinit();
            self.allocator.destroy(buffer);
        }
    }
};

// Tests
test "Gateway initialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var test_config = try config.Config.init(allocator);
    defer test_config.deinit();

    var gw = try Gateway.init(allocator, test_config);
    defer gw.deinit();

    try testing.expect(gw.server == null);
    try testing.expect(!gw.shutdown_requested.load(.Acquire));
}
