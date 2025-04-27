const std = @import("std");
const testing = std.testing;
const gateway = @import("gateway");

test "HTTP/1.1 GET request" {
    // Set up test server
    var server = try TestServer.start();
    defer server.stop();
    
    // Set up gateway with route to test server
    var gw = try TestGateway.start(server.port);
    defer gw.stop();
    
    // Send a GET request to the gateway
    var client = try std.http.Client.init(testing.allocator, .{});
    defer client.deinit();
    
    var headers = std.http.Headers.init(testing.allocator);
    defer headers.deinit();
    
    try headers.append("Host", "localhost");
    
    var request = try client.request(.GET, try std.Uri.parse("http://localhost:8080/test"), headers, .{});
    defer request.deinit();
    
    try request.start();
    try request.finish();
    
    try request.wait();
    
    // Verify response
    try testing.expectEqual(@as(u16, 200), request.response.status);
    
    const body = try request.reader().readAllAlloc(testing.allocator, 1024 * 1024);
    defer testing.allocator.free(body);
    
    try testing.expectEqualStrings("Hello, World!", body);
}

test "HTTP/1.1 POST request" {
    // Set up test server
    var server = try TestServer.start();
    defer server.stop();
    
    // Set up gateway with route to test server
    var gw = try TestGateway.start(server.port);
    defer gw.stop();
    
    // Send a POST request to the gateway
    var client = try std.http.Client.init(testing.allocator, .{});
    defer client.deinit();
    
    var headers = std.http.Headers.init(testing.allocator);
    defer headers.deinit();
    
    try headers.append("Host", "localhost");
    try headers.append("Content-Type", "application/json");
    
    var request = try client.request(.POST, try std.Uri.parse("http://localhost:8080/test"), headers, .{});
    defer request.deinit();
    
    try request.start();
    
    _ = try request.writer().write("{\"key\":\"value\"}");
    
    try request.finish();
    try request.wait();
    
    // Verify response
    try testing.expectEqual(@as(u16, 200), request.response.status);
    
    const body = try request.reader().readAllAlloc(testing.allocator, 1024 * 1024);
    defer testing.allocator.free(body);
    
    try testing.expectEqualStrings("{\"result\":\"success\"}", body);
}

/// Test server for integration tests
const TestServer = struct {
    allocator: std.mem.Allocator,
    server: std.http.Server,
    port: u16,
    thread: std.Thread,
    shutdown: std.atomic.Atomic(bool),
    
    /// Start a test server
    pub fn start() !TestServer {
        const allocator = testing.allocator;
        
        var server = std.http.Server.init(allocator, .{});
        const port = 8081;
        
        try server.listen(try std.net.Address.parseIp("127.0.0.1", port));
        
        var test_server = TestServer{
            .allocator = allocator,
            .server = server,
            .port = port,
            .thread = undefined,
            .shutdown = std.atomic.Atomic(bool).init(false),
        };
        
        test_server.thread = try std.Thread.spawn(.{}, runServer, .{&test_server});
        
        return test_server;
    }
    
    /// Stop the test server
    pub fn stop(self: *TestServer) void {
        self.shutdown.store(true, .SeqCst);
        self.thread.join();
        self.server.deinit();
    }
    
    /// Run the server in a separate thread
    fn runServer(self: *TestServer) !void {
        while (!self.shutdown.load(.SeqCst)) {
            var response = try self.server.accept(.{
                .allocator = self.allocator,
            });
            defer response.deinit();
            
            try self.handleRequest(&response);
        }
    }
    
    /// Handle a request
    fn handleRequest(self: *TestServer, response: *std.http.Server.Response) !void {
        _ = self;
        
        // Get request information
        const method = response.request.method;
        const path = response.request.target;
        
        // Handle different request types
        if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/test")) {
            try response.headers.append("Content-Type", "text/plain");
            response.transfer_encoding = .{ .content_length = 13 };
            try response.do();
            
            _ = try response.writer().write("Hello, World!");
        } else if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/test")) {
            try response.headers.append("Content-Type", "application/json");
            response.transfer_encoding = .{ .content_length = 20 };
            try response.do();
            
            _ = try response.writer().write("{\"result\":\"success\"}");
        } else {
            response.status = .not_found;
            try response.do();
        }
    }
};

/// Test gateway for integration tests
const TestGateway = struct {
    allocator: std.mem.Allocator,
    gateway: gateway.Gateway,
    thread: std.Thread,
    shutdown: std.atomic.Atomic(bool),
    
    /// Start a test gateway
    pub fn start(upstream_port: u16) !TestGateway {
        const allocator = testing.allocator;
        
        // Create configuration
        var config = try gateway.config.Config.init(allocator);
        
        // Add route to test server
        const route = try gateway.config.Route.init(
            allocator,
            "/test",
            try std.fmt.allocPrint(allocator, "http://localhost:{d}", .{upstream_port}),
            &[_][]const u8{ "GET", "POST" },
            &[_][]const u8{},
        );
        
        config.routes = try allocator.alloc(gateway.config.Route, 1);
        config.routes[0] = route;
        
        // Create gateway
        var gw = try gateway.Gateway.init(allocator, config);
        
        var test_gateway = TestGateway{
            .allocator = allocator,
            .gateway = gw,
            .thread = undefined,
            .shutdown = std.atomic.Atomic(bool).init(false),
        };
        
        test_gateway.thread = try std.Thread.spawn(.{}, runGateway, .{&test_gateway});
        
        // Wait for gateway to start
        std.time.sleep(100 * std.time.ns_per_ms);
        
        return test_gateway;
    }
    
    /// Stop the test gateway
    pub fn stop(self: *TestGateway) void {
        self.shutdown.store(true, .SeqCst);
        self.gateway.shutdown();
        self.thread.join();
        self.gateway.deinit();
    }
    
    /// Run the gateway in a separate thread
    fn runGateway(self: *TestGateway) !void {
        try self.gateway.run();
    }
};
