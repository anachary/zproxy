const std = @import("std");
const thread_pool = @import("thread_pool.zig");
const numa = @import("numa.zig");

/// High-performance connection acceptor
pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    address: std.net.Address,
    server_options: std.net.StreamServer.Options,
    servers: []std.net.StreamServer,
    acceptor_threads: []std.Thread,
    thread_pool: *thread_pool.NumaThreadPool,
    connection_handler: ConnectionHandler,
    shutdown_requested: std.atomic.Atomic(bool),
    
    /// Connection handler function type
    pub const ConnectionHandler = struct {
        function: *const fn (context: *anyopaque, connection: std.net.StreamServer.Connection) void,
        context: *anyopaque,
    };
    
    /// Initialize a new acceptor
    pub fn init(
        allocator: std.mem.Allocator,
        address: std.net.Address,
        thread_pool: *thread_pool.NumaThreadPool,
        connection_handler: ConnectionHandler,
    ) !Acceptor {
        // Determine how many acceptor threads to use
        const node_count = thread_pool.getNodeCount();
        const acceptor_count = @min(node_count, 8); // Max 8 acceptor threads
        
        // Create server options with SO_REUSEPORT
        const server_options = std.net.StreamServer.Options{
            .reuse_address = true,
            .reuse_port = true, // Enable SO_REUSEPORT for multiple listeners
            .kernel_backlog = 4096, // Larger backlog for high-throughput scenarios
        };
        
        // Create servers and acceptor threads
        var servers = try allocator.alloc(std.net.StreamServer, acceptor_count);
        errdefer allocator.free(servers);
        
        var acceptor_threads = try allocator.alloc(std.Thread, acceptor_count);
        errdefer allocator.free(acceptor_threads);
        
        // Initialize servers
        for (servers) |*server| {
            server.* = std.net.StreamServer.init(server_options);
        }
        
        var acceptor = Acceptor{
            .allocator = allocator,
            .address = address,
            .server_options = server_options,
            .servers = servers,
            .acceptor_threads = acceptor_threads,
            .thread_pool = thread_pool,
            .connection_handler = connection_handler,
            .shutdown_requested = std.atomic.Atomic(bool).init(false),
        };
        
        return acceptor;
    }
    
    /// Clean up resources
    pub fn deinit(self: *Acceptor) void {
        // Signal shutdown
        self.shutdown_requested.store(true, .Release);
        
        // Close all servers to unblock accept()
        for (self.servers) |*server| {
            server.close();
        }
        
        // Wait for all acceptor threads to finish
        for (self.acceptor_threads) |thread| {
            thread.join();
        }
        
        // Clean up resources
        for (self.servers) |*server| {
            server.deinit();
        }
        
        self.allocator.free(self.servers);
        self.allocator.free(self.acceptor_threads);
    }
    
    /// Start accepting connections
    pub fn start(self: *Acceptor) !void {
        // Get CPUs for each NUMA node
        var node_cpus = try self.allocator.alloc([]usize, self.thread_pool.getNodeCount());
        defer {
            for (node_cpus) |cpus| {
                self.allocator.free(cpus);
            }
            self.allocator.free(node_cpus);
        }
        
        for (0..self.thread_pool.getNodeCount()) |node| {
            node_cpus[node] = try numa.Numa.getCpusForNumaNode(node, self.allocator);
        }
        
        // Start listening on all servers
        for (self.servers) |*server| {
            try server.listen(self.address);
        }
        
        // Start acceptor threads
        for (self.acceptor_threads, 0..) |*thread, i| {
            const node = i % self.thread_pool.getNodeCount();
            const cpu_id = node_cpus[node][0]; // Use first CPU in the node
            
            const thread_context = try self.allocator.create(AcceptorThreadContext);
            thread_context.* = AcceptorThreadContext{
                .acceptor = self,
                .server_index = i,
                .node = node,
                .cpu_id = cpu_id,
            };
            
            thread.* = try std.Thread.spawn(.{}, acceptorThread, .{thread_context});
        }
    }
    
    /// Context for acceptor thread
    const AcceptorThreadContext = struct {
        acceptor: *Acceptor,
        server_index: usize,
        node: usize,
        cpu_id: usize,
    };
    
    /// Acceptor thread function
    fn acceptorThread(context: *AcceptorThreadContext) !void {
        const acceptor = context.acceptor;
        const server_index = context.server_index;
        const node = context.node;
        const cpu_id = context.cpu_id;
        
        // Free the context
        defer acceptor.allocator.destroy(context);
        
        const logger = std.log.scoped(.acceptor);
        logger.debug("Acceptor thread {d} started on NUMA node {d}, CPU {d}", .{
            server_index, 
            node, 
            cpu_id,
        });
        
        // Set CPU affinity
        try numa.Numa.setThreadAffinity(cpu_id);
        
        // Get the server for this thread
        var server = &acceptor.servers[server_index];
        
        // Accept connections until shutdown is requested
        while (!acceptor.shutdown_requested.load(.Acquire)) {
            // Accept a connection
            const connection = server.accept() catch |err| {
                if (err == error.ConnectionAborted or 
                    err == error.ConnectionResetByPeer or
                    err == error.WouldBlock) 
                {
                    // These are common errors, just continue
                    continue;
                }
                
                if (acceptor.shutdown_requested.load(.Acquire)) {
                    // Shutdown requested, exit
                    break;
                }
                
                logger.err("Error accepting connection: {}", .{err});
                continue;
            };
            
            // Create connection handler context
            var conn_context = try acceptor.allocator.create(ConnectionContext);
            conn_context.* = ConnectionContext{
                .handler = acceptor.connection_handler,
                .connection = connection,
                .node = node,
            };
            
            // Add connection handling job to thread pool
            try acceptor.thread_pool.addJob(
                connectionHandlerJob,
                @ptrCast(conn_context),
                node, // Prefer the same NUMA node
            );
        }
        
        logger.debug("Acceptor thread {d} shutting down", .{server_index});
    }
    
    /// Context for connection handler
    const ConnectionContext = struct {
        handler: ConnectionHandler,
        connection: std.net.StreamServer.Connection,
        node: usize,
    };
    
    /// Connection handler job function
    fn connectionHandlerJob(context_ptr: *anyopaque) void {
        const context = @as(*ConnectionContext, @ptrCast(@alignCast(context_ptr)));
        defer context.handler.function(context.handler.context, context.connection);
    }
};

/// Accept connections in a high-performance way
pub fn acceptConnections(
    allocator: std.mem.Allocator,
    address: std.net.Address,
    thread_pool: *thread_pool.NumaThreadPool,
    connection_handler: Acceptor.ConnectionHandler,
) !*Acceptor {
    var acceptor = try allocator.create(Acceptor);
    errdefer allocator.destroy(acceptor);
    
    acceptor.* = try Acceptor.init(
        allocator,
        address,
        thread_pool,
        connection_handler,
    );
    
    try acceptor.start();
    
    return acceptor;
}
