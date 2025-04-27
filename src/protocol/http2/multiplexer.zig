const std = @import("std");
const frames = @import("frames.zig");
const streams = @import("streams.zig");
const utils = @import("../../utils/allocator.zig");

/// HTTP/2 multiplexer for handling multiple streams concurrently
pub const Multiplexer = struct {
    allocator: std.mem.Allocator,
    connection: *frames.Connection,
    stream_manager: streams.StreamManager,
    active_streams: std.atomic.Atomic(usize),
    mutex: std.Thread.Mutex,
    upstream_connections: std.StringHashMap(*UpstreamConnection),
    
    /// Initialize a new multiplexer
    pub fn init(allocator: std.mem.Allocator, connection: *frames.Connection) !*Multiplexer {
        var multiplexer = try allocator.create(Multiplexer);
        errdefer allocator.destroy(multiplexer);
        
        var stream_manager = try streams.StreamManager.init(allocator);
        errdefer stream_manager.deinit();
        
        multiplexer.* = Multiplexer{
            .allocator = allocator,
            .connection = connection,
            .stream_manager = stream_manager,
            .active_streams = std.atomic.Atomic(usize).init(0),
            .mutex = std.Thread.Mutex{},
            .upstream_connections = std.StringHashMap(*UpstreamConnection).init(allocator),
        };
        
        return multiplexer;
    }
    
    /// Clean up resources
    pub fn deinit(self: *Multiplexer) void {
        self.stream_manager.deinit();
        
        // Close all upstream connections
        var it = self.upstream_connections.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        
        self.upstream_connections.deinit();
    }
    
    /// Process a frame
    pub fn processFrame(self: *Multiplexer, frame: frames.Frame) !void {
        const logger = std.log.scoped(.http2_multiplexer);
        
        // Handle connection-level frames
        switch (frame.header.type) {
            .SETTINGS => {
                logger.debug("Processing SETTINGS frame", .{});
                try self.processSettingsFrame(frame);
                return;
            },
            .PING => {
                logger.debug("Processing PING frame", .{});
                try self.processPingFrame(frame);
                return;
            },
            .GOAWAY => {
                logger.debug("Processing GOAWAY frame", .{});
                return error.ConnectionClosed;
            },
            .WINDOW_UPDATE => {
                if (frame.header.stream_id == 0) {
                    // Connection-level window update
                    logger.debug("Processing connection-level WINDOW_UPDATE frame", .{});
                    try self.processWindowUpdateFrame(frame);
                    return;
                }
                // Stream-level window updates are handled below
            },
            else => {},
        }
        
        // Handle stream-level frames
        if (frame.header.stream_id == 0) {
            logger.warn("Received stream-level frame with stream ID 0", .{});
            return error.ProtocolError;
        }
        
        // Get or create the stream
        var stream = self.stream_manager.getStream(@intCast(frame.header.stream_id));
        if (stream == null) {
            if (frame.header.type != .HEADERS) {
                logger.warn("Received frame for non-existent stream {d}", .{frame.header.stream_id});
                try self.connection.sendRstStream(frame.header.stream_id, .PROTOCOL_ERROR);
                return;
            }
            
            // Create a new stream for HEADERS frame
            stream = try self.stream_manager.createIncomingStream(
                self.connection,
                @intCast(frame.header.stream_id),
            );
        }
        
        // Update stream state based on frame
        stream.?.updateState(frame);
        
        // Process the frame based on type
        switch (frame.header.type) {
            .HEADERS => {
                logger.debug("Processing HEADERS frame for stream {d}", .{frame.header.stream_id});
                try self.processHeadersFrame(stream.?, frame);
            },
            .DATA => {
                logger.debug("Processing DATA frame for stream {d}", .{frame.header.stream_id});
                try self.processDataFrame(stream.?, frame);
            },
            .RST_STREAM => {
                logger.debug("Processing RST_STREAM frame for stream {d}", .{frame.header.stream_id});
                self.stream_manager.closeStream(@intCast(frame.header.stream_id));
            },
            .WINDOW_UPDATE => {
                logger.debug("Processing stream-level WINDOW_UPDATE frame for stream {d}", .{frame.header.stream_id});
                try self.processStreamWindowUpdateFrame(stream.?, frame);
            },
            .PRIORITY => {
                logger.debug("Processing PRIORITY frame for stream {d}", .{frame.header.stream_id});
                // Handle stream priority
            },
            .CONTINUATION => {
                logger.debug("Processing CONTINUATION frame for stream {d}", .{frame.header.stream_id});
                // Handle continuation of headers
            },
            else => {
                logger.warn("Received unexpected frame type for stream {d}: {}", .{
                    frame.header.stream_id,
                    @intFromEnum(frame.header.type),
                });
            },
        }
        
        // Clean up closed streams periodically
        if (self.active_streams.load(.Acquire) % 10 == 0) {
            self.stream_manager.removeClosedStreams();
        }
    }
    
    /// Process a SETTINGS frame
    fn processSettingsFrame(self: *Multiplexer, frame: frames.Frame) !void {
        // ACK the SETTINGS frame
        try self.connection.sendSettingsAck();
        
        // Apply settings
        if (frame.payload.len > 0) {
            const settings = try frames.parseSettings(frame.payload);
            self.connection.applySettings(settings);
            
            // Update stream manager with new settings
            if (settings.max_concurrent_streams) |max| {
                self.stream_manager.max_concurrent_streams = max;
            }
        }
    }
    
    /// Process a PING frame
    fn processPingFrame(self: *Multiplexer, frame: frames.Frame) !void {
        // Send PING ACK with the same payload
        try self.connection.sendPingAck(frame.payload);
    }
    
    /// Process a connection-level WINDOW_UPDATE frame
    fn processWindowUpdateFrame(self: *Multiplexer, frame: frames.Frame) !void {
        if (frame.payload.len != 4) {
            return error.ProtocolError;
        }
        
        // Parse the window size increment
        var value_bytes: [4]u8 = undefined;
        @memcpy(&value_bytes, frame.payload[0..4]);
        const increment = std.mem.readIntBig(u32, &value_bytes);
        
        // Update connection window size
        // In a real implementation, track and enforce flow control
        _ = increment;
    }
    
    /// Process a stream-level WINDOW_UPDATE frame
    fn processStreamWindowUpdateFrame(self: *Multiplexer, stream: *streams.Stream, frame: frames.Frame) !void {
        if (frame.payload.len != 4) {
            return error.ProtocolError;
        }
        
        // Parse the window size increment
        var value_bytes: [4]u8 = undefined;
        @memcpy(&value_bytes, frame.payload[0..4]);
        const increment = std.mem.readIntBig(u32, &value_bytes);
        
        // Update stream window size
        stream.window_size += increment;
    }
    
    /// Process a HEADERS frame
    fn processHeadersFrame(self: *Multiplexer, stream: *streams.Stream, frame: frames.Frame) !void {
        // Parse headers
        const headers = try frames.parseHeaders(
            self.allocator,
            frame.payload,
        );
        defer {
            for (headers) |header| {
                self.allocator.free(header.name);
                self.allocator.free(header.value);
            }
            self.allocator.free(headers);
        }
        
        // Extract method, path, etc.
        var method: ?[]const u8 = null;
        var path: ?[]const u8 = null;
        var scheme: ?[]const u8 = null;
        var authority: ?[]const u8 = null;
        
        for (headers) |header| {
            if (std.mem.eql(u8, header.name, ":method")) {
                method = header.value;
            } else if (std.mem.eql(u8, header.name, ":path")) {
                path = header.value;
            } else if (std.mem.eql(u8, header.name, ":scheme")) {
                scheme = header.value;
            } else if (std.mem.eql(u8, header.name, ":authority")) {
                authority = header.value;
            }
        }
        
        if (method == null or path == null) {
            // Send protocol error
            try self.connection.sendRstStream(frame.header.stream_id, .PROTOCOL_ERROR);
            return;
        }
        
        // Store headers in stream for later use
        try stream.setHeaders(headers);
        
        // Check if this is the end of the request
        const end_stream = (frame.header.flags & frames.FrameFlags.END_STREAM) != 0;
        if (end_stream) {
            // Process the complete request
            try self.handleRequest(stream);
        }
    }
    
    /// Process a DATA frame
    fn processDataFrame(self: *Multiplexer, stream: *streams.Stream, frame: frames.Frame) !void {
        // Append data to stream's body buffer
        try stream.appendData(frame.payload);
        
        // Check if this is the end of the request
        const end_stream = (frame.header.flags & frames.FrameFlags.END_STREAM) != 0;
        if (end_stream) {
            // Process the complete request
            try self.handleRequest(stream);
        }
    }
    
    /// Handle a complete HTTP request
    fn handleRequest(self: *Multiplexer, stream: *streams.Stream) !void {
        const logger = std.log.scoped(.http2_request);
        
        // Increment active streams counter
        _ = self.active_streams.fetchAdd(1, .Release);
        defer _ = self.active_streams.fetchSub(1, .Release);
        
        // Get request details from stream
        const headers = stream.getHeaders() orelse {
            logger.err("Stream has no headers", .{});
            try stream.resetStream(.INTERNAL_ERROR);
            return;
        };
        
        // Extract method and path
        var method: ?[]const u8 = null;
        var path: ?[]const u8 = null;
        
        for (headers) |header| {
            if (std.mem.eql(u8, header.name, ":method")) {
                method = header.value;
            } else if (std.mem.eql(u8, header.name, ":path")) {
                path = header.value;
            }
        }
        
        if (method == null or path == null) {
            logger.err("Missing required headers", .{});
            try stream.resetStream(.PROTOCOL_ERROR);
            return;
        }
        
        logger.info("HTTP/2 request: {s} {s}", .{ method.?, path.? });
        
        // TODO: Find route and apply middleware
        // For now, just send a mock response
        const response_headers = [_]frames.Header{
            .{ .name = ":status", .value = "200" },
            .{ .name = "content-type", .value = "text/plain" },
            .{ .name = "server", .value = "ZProxy" },
        };
        
        try stream.sendHeaders(response_headers[0..], false);
        
        const response_body = "Hello from ZProxy HTTP/2!";
        try stream.sendData(response_body, true);
    }
    
    /// Get or create an upstream connection
    pub fn getUpstreamConnection(self: *Multiplexer, upstream_url: []const u8) !*UpstreamConnection {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Check if we already have a connection to this upstream
        if (self.upstream_connections.get(upstream_url)) |conn| {
            return conn;
        }
        
        // Create a new connection
        var upstream = try UpstreamConnection.init(self.allocator, upstream_url);
        errdefer upstream.deinit();
        
        // Store the connection
        try self.upstream_connections.put(
            try self.allocator.dupe(u8, upstream_url),
            upstream,
        );
        
        return upstream;
    }
};

/// Connection to an upstream HTTP/2 server
pub const UpstreamConnection = struct {
    allocator: std.mem.Allocator,
    url: []const u8,
    stream: ?std.net.Stream,
    connection: ?frames.Connection,
    stream_manager: ?streams.StreamManager,
    connected: bool,
    mutex: std.Thread.Mutex,
    
    /// Initialize a new upstream connection
    pub fn init(allocator: std.mem.Allocator, url: []const u8) !*UpstreamConnection {
        var upstream = try allocator.create(UpstreamConnection);
        
        upstream.* = UpstreamConnection{
            .allocator = allocator,
            .url = try allocator.dupe(u8, url),
            .stream = null,
            .connection = null,
            .stream_manager = null,
            .connected = false,
            .mutex = std.Thread.Mutex{},
        };
        
        return upstream;
    }
    
    /// Clean up resources
    pub fn deinit(self: *UpstreamConnection) void {
        if (self.stream_manager) |*sm| {
            sm.deinit();
        }
        
        if (self.connection) |*conn| {
            conn.deinit();
        }
        
        if (self.stream) |*s| {
            s.close();
        }
        
        self.allocator.free(self.url);
    }
    
    /// Connect to the upstream server
    pub fn connect(self: *UpstreamConnection) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.connected) {
            return;
        }
        
        // Parse the URL
        var uri = try std.Uri.parse(self.url);
        const host = uri.host orelse return error.InvalidUpstreamUrl;
        const port = uri.port orelse if (std.mem.eql(u8, uri.scheme, "https")) 443 else 80;
        
        // Connect to the server
        const address = try std.net.Address.parseIp(host, port);
        var stream = try std.net.tcpConnectToAddress(address);
        errdefer stream.close();
        
        // Set TCP options for better performance
        try stream.setNoDelay(true);
        try stream.setTcpKeepAlive(true);
        
        // Initialize HTTP/2 connection
        var connection = try frames.Connection.init(self.allocator, stream);
        errdefer connection.deinit();
        
        // Initialize stream manager
        var stream_manager = try streams.StreamManager.init(self.allocator);
        errdefer stream_manager.deinit();
        
        // Send connection preface and initial SETTINGS
        try self.sendConnectionPreface(&connection);
        
        // Store the connection
        self.stream = stream;
        self.connection = connection;
        self.stream_manager = stream_manager;
        self.connected = true;
    }
    
    /// Send HTTP/2 connection preface
    fn sendConnectionPreface(self: *UpstreamConnection, connection: *frames.Connection) !void {
        _ = self;
        
        // Send the connection preface
        const preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
        _ = try connection.stream.write(preface);
        
        // Send initial SETTINGS frame
        try connection.sendSettings(.{
            .max_concurrent_streams = 100,
            .initial_window_size = 65535,
            .max_frame_size = 16384,
        });
    }
    
    /// Create a new stream to the upstream server
    pub fn createStream(self: *UpstreamConnection) !*streams.Stream {
        if (!self.connected) {
            try self.connect();
        }
        
        return self.stream_manager.?.createStream(
            &self.connection.?,
        );
    }
    
    /// Send a request to the upstream server
    pub fn sendRequest(
        self: *UpstreamConnection,
        method: []const u8,
        path: []const u8,
        headers: []const frames.Header,
        body: ?[]const u8,
    ) !*streams.Stream {
        if (!self.connected) {
            try self.connect();
        }
        
        // Create a new stream
        var stream = try self.createStream();
        
        // Prepare headers
        var all_headers = std.ArrayList(frames.Header).init(self.allocator);
        defer all_headers.deinit();
        
        // Add pseudo-headers
        try all_headers.append(.{ .name = ":method", .value = method });
        try all_headers.append(.{ .name = ":path", .value = path });
        try all_headers.append(.{ .name = ":scheme", .value = "http" }); // or https
        try all_headers.append(.{ .name = ":authority", .value = "example.com" }); // TODO: Extract from URL
        
        // Add regular headers
        for (headers) |header| {
            try all_headers.append(header);
        }
        
        // Send headers
        const end_stream = body == null;
        try stream.sendHeaders(all_headers.items, end_stream);
        
        // Send body if present
        if (body) |data| {
            try stream.sendData(data, true);
        }
        
        return stream;
    }
};
