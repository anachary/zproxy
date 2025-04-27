const std = @import("std");

// Re-export modules
pub const config = @import("config/config.zig");
pub const protocol = @import("protocol/detector.zig");
pub const router = @import("router/router.zig");
pub const middleware = @import("middleware/middleware.zig");
pub const tls = @import("tls/manager.zig");
pub const metrics = @import("metrics/collector.zig");
pub const utils = @import("utils/allocator.zig");

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

        return Gateway{
            .allocator = allocator,
            .config = cfg,
            .router = router_instance,
            .tls_manager = tls_manager_instance,
            .metrics_collector = metrics_collector_instance,
            .shutdown_requested = std.atomic.Atomic(bool).init(false),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Gateway) void {
        if (self.server) |*server| {
            server.deinit();
        }
        self.router.deinit();
        self.tls_manager.deinit();
        self.metrics_collector.deinit();
    }

    /// Start the gateway and begin accepting connections
    pub fn run(self: *Gateway) !void {
        const logger = std.log.scoped(.gateway);
        logger.info("Starting gateway on {s}:{d}", .{
            self.config.listen_address,
            self.config.listen_port,
        });

        // Create server
        const address = try std.net.Address.parseIp(
            self.config.listen_address,
            self.config.listen_port,
        );
        self.server = std.net.StreamServer.init(.{});
        try self.server.?.listen(address);

        // Accept connections until shutdown is requested
        while (!self.shutdown_requested.load(.Acquire)) {
            const connection = try self.server.?.accept();
            // Handle connection in a separate thread
            _ = try std.Thread.spawn(.{}, handleConnection, .{
                self,
                connection,
            });
        }
    }

    /// Request a graceful shutdown of the gateway
    pub fn shutdown(self: *Gateway) void {
        self.shutdown_requested.store(true, .Release);
        if (self.server) |*server| {
            server.close();
        }
    }

    /// Handle a single client connection
    fn handleConnection(self: *Gateway, connection: std.net.StreamServer.Connection) !void {
        const logger = std.log.scoped(.connection);
        logger.debug("New connection from {}", .{connection.address});

        // Set up connection context
        var conn_context = try ConnectionContext.init(
            self.allocator,
            connection,
            &self.router,
            &self.metrics_collector,
        );
        defer conn_context.deinit();

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
    }
};

/// Context for a single client connection
const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    connection: std.net.StreamServer.Connection,
    router: *router.Router,
    metrics_collector: *metrics.Collector,
    buffer: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        connection: std.net.StreamServer.Connection,
        route_handler: *router.Router,
        metrics_collector: *metrics.Collector,
    ) !ConnectionContext {
        const buffer = try allocator.alloc(u8, 8192);
        return ConnectionContext{
            .allocator = allocator,
            .connection = connection,
            .router = route_handler,
            .metrics_collector = metrics_collector,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *ConnectionContext) void {
        self.allocator.free(self.buffer);
        self.connection.stream.close();
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
