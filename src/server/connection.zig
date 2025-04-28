const std = @import("std");
const logger = @import("../utils/logger.zig");
const protocol = @import("../protocol/detector.zig");
const http1 = @import("../protocol/http1.zig");
const http2 = @import("../protocol/http2.zig");
const websocket = @import("../protocol/websocket.zig");
const Server = @import("server.zig").Server;

/// Connection context
pub const Connection = struct {
    stream: std.net.Stream,
    client_addr: std.net.Address,
    server: *Server,
    
    /// Handle a connection
    pub fn handle(self: *Connection) !void {
        defer self.stream.close();
        
        logger.debug("Handling connection from {}", .{self.client_addr});
        
        // Set connection timeout
        try self.stream.setReadTimeout(self.server.config.connection_timeout_ms * std.time.ns_per_ms);
        try self.stream.setWriteTimeout(self.server.config.connection_timeout_ms * std.time.ns_per_ms);
        
        // Detect protocol
        const detected_protocol = try protocol.detectProtocol(self.stream);
        logger.debug("Detected protocol: {s}", .{@tagName(detected_protocol)});
        
        // Handle protocol
        switch (detected_protocol) {
            .http1 => try self.handleHttp1(),
            .http2 => try self.handleHttp2(),
            .websocket => try self.handleWebsocket(),
            .unknown => {
                logger.warning("Unknown protocol from {}", .{self.client_addr});
                return error.UnknownProtocol;
            },
        }
    }
    
    /// Handle HTTP/1.1 connection
    fn handleHttp1(self: *Connection) !void {
        // Read request
        var buffer: [8192]u8 = undefined;
        const bytes_read = try self.stream.read(&buffer);
        
        if (bytes_read == 0) {
            logger.debug("Empty request from {}", .{self.client_addr});
            return;
        }
        
        // Parse request (simplified for now)
        const request = try http1.parseRequest(self.server.allocator, buffer[0..bytes_read], self.client_addr);
        defer request.deinit();
        
        // Find route
        const route = self.server.router.findRoute(request.path, request.method);
        if (route == null) {
            logger.debug("No route found for {s} {s}", .{ request.method, request.path });
            try self.sendNotFound();
            return;
        }
        
        // Apply middleware
        const middleware_result = try self.server.middleware.apply(request, route.?);
        if (!middleware_result.allowed) {
            logger.debug("Request blocked by middleware: {s}", .{middleware_result.reason});
            try self.sendForbidden(middleware_result.reason);
            return;
        }
        
        // Forward request to upstream (simplified for now)
        try self.sendOk();
    }
    
    /// Handle HTTP/2 connection
    fn handleHttp2(self: *Connection) !void {
        try http2.handleConnection(self.stream, self.client_addr);
    }
    
    /// Handle WebSocket connection
    fn handleWebsocket(self: *Connection) !void {
        // Read request
        var buffer: [8192]u8 = undefined;
        const bytes_read = try self.stream.read(&buffer);
        
        if (bytes_read == 0) {
            logger.debug("Empty request from {}", .{self.client_addr});
            return;
        }
        
        // Parse request
        const request = try http1.parseRequest(self.server.allocator, buffer[0..bytes_read], self.client_addr);
        defer request.deinit();
        
        // Handle WebSocket connection
        try websocket.handleConnection(self.server.allocator, self.stream, self.client_addr, request);
    }
    
    /// Send 200 OK response
    fn sendOk(self: *Connection) !void {
        const response =
            \\HTTP/1.1 200 OK
            \\Content-Type: text/plain
            \\Content-Length: 2
            \\Connection: close
            \\
            \\OK
        ;
        
        _ = try self.stream.write(response);
    }
    
    /// Send 404 Not Found response
    fn sendNotFound(self: *Connection) !void {
        const response =
            \\HTTP/1.1 404 Not Found
            \\Content-Type: text/plain
            \\Content-Length: 9
            \\Connection: close
            \\
            \\Not Found
        ;
        
        _ = try self.stream.write(response);
    }
    
    /// Send 403 Forbidden response
    fn sendForbidden(self: *Connection, reason: []const u8) !void {
        const header =
            \\HTTP/1.1 403 Forbidden
            \\Content-Type: text/plain
            \\Connection: close
            \\
            \\
        ;
        
        _ = try self.stream.write(header);
        _ = try self.stream.write(reason);
    }
    
    /// Send 501 Not Implemented response
    fn sendNotImplemented(self: *Connection) !void {
        const response =
            \\HTTP/1.1 501 Not Implemented
            \\Content-Type: text/plain
            \\Content-Length: 15
            \\Connection: close
            \\
            \\Not Implemented
        ;
        
        _ = try self.stream.write(response);
    }
};
