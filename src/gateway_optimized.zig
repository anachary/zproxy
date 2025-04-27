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

/// Optimized buffer pools for efficient memory reuse
pub const ConnectionBufferPool = struct {
    buffer_pool: utils.buffer.BufferPool,
    zero_copy_pool: utils.zero_copy.ZeroCopyBufferPool,
    vectored_pool: vectored_io_mod.VectoredBufferPool,
    
    /// Initialize a new connection buffer pool
    pub fn init(allocator: std.mem.Allocator) !ConnectionBufferPool {
        return ConnectionBufferPool{
            .buffer_pool = utils.buffer.BufferPool.init(allocator, 32768, 1000),
            .zero_copy_pool = utils.zero_copy.ZeroCopyBufferPool.init(allocator, 65536, 100),
            .vectored_pool = vectored_io_mod.VectoredBufferPool.init(allocator, 32, 100),
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *ConnectionBufferPool) void {
        self.buffer_pool.deinit();
        self.zero_copy_pool.deinit();
        self.vectored_pool.deinit();
    }
    
    /// Get a buffer from the pool
    pub fn getBuffer(self: *ConnectionBufferPool) ![]u8 {
        return self.buffer_pool.getBuffer();
    }
    
    /// Return a buffer to the pool
    pub fn returnBuffer(self: *ConnectionBufferPool, buffer: []u8) void {
        self.buffer_pool.returnBuffer(buffer);
    }
    
    /// Get a zero-copy buffer from the pool
    pub fn getZeroCopyBuffer(self: *ConnectionBufferPool) !*utils.zero_copy.ZeroCopyBuffer {
        return self.zero_copy_pool.getBuffer();
    }
    
    /// Return a zero-copy buffer to the pool
    pub fn returnZeroCopyBuffer(self: *ConnectionBufferPool, buffer: *utils.zero_copy.ZeroCopyBuffer) void {
        self.zero_copy_pool.returnBuffer(buffer);
    }
    
    /// Get a vectored buffer from the pool
    pub fn getVectoredBuffer(self: *ConnectionBufferPool) !*vectored_io_mod.VectoredBuffer {
        return self.vectored_pool.getBuffer();
    }
    
    /// Return a vectored buffer to the pool
    pub fn returnVectoredBuffer(self: *ConnectionBufferPool, buffer: *vectored_io_mod.VectoredBuffer) void {
        self.vectored_pool.returnBuffer(buffer);
    }
};

/// Context for a single client connection
pub const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    connection: std.net.StreamServer.Connection,
    router: *router.Router,
    metrics_collector: *metrics.Collector,
    buffer: []u8,
    owns_buffer: bool,
    timer: utils.time.Timer,
    zero_copy_pool: ?*utils.zero_copy.ZeroCopyBufferPool,
    vectored_pool: ?*vectored_io_mod.VectoredBufferPool,
    numa_node: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        connection: std.net.StreamServer.Connection,
        route_handler: *router.Router,
        metrics_collector: *metrics.Collector,
        buffer: ?[]u8,
        numa_node: usize,
    ) !ConnectionContext {
        // Initialize with default timer (will be reset when handling starts)
        const timer = utils.time.Timer.start();

        // Create a shared zero-copy buffer pool for this connection
        var zero_copy_pool = try allocator.create(utils.zero_copy.ZeroCopyBufferPool);
        zero_copy_pool.* = utils.zero_copy.ZeroCopyBufferPool.init(allocator, 65536, 4);
        
        // Create a shared vectored buffer pool for this connection
        var vectored_pool = try allocator.create(vectored_io_mod.VectoredBufferPool);
        vectored_pool.* = vectored_io_mod.VectoredBufferPool.init(allocator, 32, 4);

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
                .vectored_pool = vectored_pool,
                .numa_node = numa_node,
            };
        } else {
            const new_buffer = try allocator.alloc(u8, 32768);
            return ConnectionContext{
                .allocator = allocator,
                .connection = connection,
                .router = route_handler,
                .metrics_collector = metrics_collector,
                .buffer = new_buffer,
                .owns_buffer = true,
                .timer = timer,
                .zero_copy_pool = zero_copy_pool,
                .vectored_pool = vectored_pool,
                .numa_node = numa_node,
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
        
        // Clean up vectored buffer pool
        if (self.vectored_pool) |pool| {
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
    
    /// Get a vectored buffer from the pool
    pub fn getVectoredBuffer(self: *ConnectionContext) !*vectored_io_mod.VectoredBuffer {
        if (self.vectored_pool) |pool| {
            return pool.getBuffer();
        }
        
        // Fallback to creating a new buffer if no pool is available
        var buffer = try self.allocator.create(vectored_io_mod.VectoredBuffer);
        buffer.* = try vectored_io_mod.VectoredBuffer.init(self.allocator, 32);
        return buffer;
    }
    
    /// Return a vectored buffer to the pool
    pub fn returnVectoredBuffer(self: *ConnectionContext, buffer: *vectored_io_mod.VectoredBuffer) void {
        if (self.vectored_pool) |pool| {
            pool.returnBuffer(buffer);
        } else {
            buffer.deinit();
            self.allocator.destroy(buffer);
        }
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
    shutdown_requested: std.atomic.Atomic(bool),
    thread_pool: *thread_pool_mod.NumaThreadPool,
    buffer_pool: ConnectionBufferPool,
    acceptor: ?*acceptor_mod.Acceptor,
    numa_allocators: []numa_mod.NumaAllocator,
    
    /// Connection handler context
    const ConnectionHandlerContext = struct {
        gateway: *Gateway,
        connection: std.net.StreamServer.Connection,
        node: usize,
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
        
        // Create NUMA-aware thread pool
        var thread_pool = try allocator.create(thread_pool_mod.NumaThreadPool);
        thread_pool.* = try thread_pool_mod.NumaThreadPool.init(allocator);
        errdefer {
            thread_pool.deinit();
            allocator.destroy(thread_pool);
        }
        
        // Create buffer pool
        var buffer_pool = try ConnectionBufferPool.init(allocator);
        errdefer buffer_pool.deinit();
        
        // Create NUMA allocators for each node
        const node_count = thread_pool.getNodeCount();
        var numa_allocators = try allocator.alloc(numa_mod.NumaAllocator, node_count);
        errdefer allocator.free(numa_allocators);
        
        for (0..node_count) |node| {
            numa_allocators[node] = numa_mod.NumaAllocator.init(allocator, node);
        }

        return Gateway{
            .allocator = allocator,
            .config = cfg,
            .router = router_instance,
            .tls_manager = tls_manager_instance,
            .metrics_collector = metrics_collector_instance,
            .shutdown_requested = std.atomic.Atomic(bool).init(false),
            .thread_pool = thread_pool,
            .buffer_pool = buffer_pool,
            .acceptor = null,
            .numa_allocators = numa_allocators,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Gateway) void {
        if (self.acceptor) |acceptor| {
            acceptor.deinit();
            self.allocator.destroy(acceptor);
        }
        
        self.thread_pool.deinit();
        self.allocator.destroy(self.thread_pool);
        
        self.buffer_pool.deinit();
        self.router.deinit();
        self.tls_manager.deinit();
        self.metrics_collector.deinit();
        
        self.allocator.free(self.numa_allocators);
    }

    /// Start the gateway and begin accepting connections
    pub fn run(self: *Gateway) !void {
        const logger = std.log.scoped(.gateway);
        logger.info("Starting gateway on {s}:{d} with {d} worker threads across {d} NUMA nodes", .{
            self.config.listen_address,
            self.config.listen_port,
            self.thread_pool.getThreadCount(),
            self.thread_pool.getNodeCount(),
        });

        // Create address
        const address = try std.net.Address.parseIp(
            self.config.listen_address,
            self.config.listen_port,
        );
        
        // Create connection handler
        const connection_handler = acceptor_mod.Acceptor.ConnectionHandler{
            .function = connectionHandlerFunction,
            .context = self,
        };
        
        // Create and start the acceptor
        self.acceptor = try acceptor_mod.acceptConnections(
            self.allocator,
            address,
            self.thread_pool,
            connection_handler,
        );
        
        // Wait for shutdown signal
        while (!self.shutdown_requested.load(.Acquire)) {
            std.time.sleep(100 * std.time.ns_per_ms);
        }
        
        logger.info("Shutdown requested, stopping acceptor", .{});
    }

    /// Request a graceful shutdown of the gateway
    pub fn shutdown(self: *Gateway) void {
        self.shutdown_requested.store(true, .Release);
    }
    
    /// Connection handler function for acceptor
    fn connectionHandlerFunction(context: *anyopaque, connection: std.net.StreamServer.Connection) void {
        const gateway = @as(*Gateway, @ptrCast(@alignCast(context)));
        
        // Get the NUMA node for this connection
        const node = @mod(@as(usize, @intFromPtr(&connection)), gateway.thread_pool.getNodeCount());
        
        // Create connection handler context
        var handler_context = gateway.allocator.create(ConnectionHandlerContext) catch |err| {
            const logger = std.log.scoped(.connection);
            logger.err("Error creating connection handler context: {}", .{err});
            connection.stream.close();
            return;
        };
        
        handler_context.* = ConnectionHandlerContext{
            .gateway = gateway,
            .connection = connection,
            .node = node,
        };
        
        // Add connection handling job to thread pool
        gateway.thread_pool.addJob(
            connectionHandlerJob,
            @ptrCast(handler_context),
            node, // Prefer the same NUMA node
        ) catch |err| {
            const logger = std.log.scoped(.connection);
            logger.err("Error adding connection handler job: {}", .{err});
            gateway.allocator.destroy(handler_context);
            connection.stream.close();
        };
    }
    
    /// Connection handler job function for thread pool
    fn connectionHandlerJob(context_ptr: *anyopaque) void {
        const context = @as(*ConnectionHandlerContext, @ptrCast(@alignCast(context_ptr)));
        defer context.gateway.allocator.destroy(context);
        
        handleConnection(context.gateway, context.connection, context.node) catch |err| {
            const logger = std.log.scoped(.connection);
            logger.err("Error handling connection: {}", .{err});
        };
    }

    /// Handle a single client connection
    fn handleConnection(self: *Gateway, connection: std.net.StreamServer.Connection, node: usize) !void {
        const logger = std.log.scoped(.connection);
        logger.debug("New connection from {} on NUMA node {d}", .{connection.address, node});
        
        // Get a buffer from the pool
        const buffer = try self.buffer_pool.getBuffer();
        defer self.buffer_pool.returnBuffer(buffer);
        
        // Get NUMA-local allocator
        var numa_allocator = self.numa_allocators[node].allocator();

        // Set up connection context with pooled buffer
        var conn_context = try ConnectionContext.init(
            numa_allocator,
            connection,
            &self.router,
            &self.metrics_collector,
            buffer,
            node,
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
