const std = @import("std");
const frames = @import("frames.zig");
const streams = @import("streams.zig");
const multiplexer_mod = @import("multiplexer.zig");
const utils = @import("../../utils/allocator.zig");

/// Handle an HTTP/2 connection
pub fn handle(conn_context: anytype) !void {
    const logger = std.log.scoped(.http2_handler);
    logger.debug("Handling HTTP/2 connection", .{});

    // Use an arena allocator for the connection lifetime
    var arena = utils.ArenaAllocator.init(conn_context.allocator);
    defer arena.deinit();
    const arena_allocator = arena.getAllocator();

    // Start timer for metrics
    var timer = utils.time.Timer.start();

    // Initialize HTTP/2 connection state
    var h2_conn = try frames.Connection.init(
        arena_allocator,
        conn_context.connection.stream,
    );
    defer h2_conn.deinit();

    // Set TCP options for better performance
    try conn_context.connection.stream.setNoDelay(true);

    // Create multiplexer for handling multiple streams
    var multiplexer = try multiplexer_mod.Multiplexer.init(arena_allocator, &h2_conn);
    defer multiplexer.deinit();

    // Send initial SETTINGS frame with optimized values
    try h2_conn.sendSettings(.{
        .max_concurrent_streams = 256, // Allow more concurrent streams
        .initial_window_size = 1048576, // 1MB window size for better throughput
        .max_frame_size = 16384, // Maximum frame size
        .header_table_size = 4096, // HPACK header table size
    });

    // Process frames until connection is closed
    while (true) {
        const frame = h2_conn.readFrame() catch |err| {
            if (err == error.EndOfStream) {
                logger.debug("Connection closed", .{});
                break;
            }

            if (err == error.ConnectionReset or
                err == error.BrokenPipe or
                err == error.ConnectionAborted)
            {
                logger.debug("Connection error: {}", .{err});
                break;
            }

            return err;
        };

        // Use the multiplexer to process the frame
        multiplexer.processFrame(frame) catch |err| {
            if (err == error.ConnectionClosed) {
                logger.debug("Connection closed by peer", .{});
                break;
            }

            logger.warn("Error processing frame: {}", .{err});
            // Continue processing other frames
        };

        // Record metrics
        try conn_context.metrics_collector.incrementCounter("http2.frames_processed", 1);
    }

    // Record final metrics
    const elapsed = timer.elapsedMillis();
    try conn_context.metrics_collector.recordHistogram("http2.connection_duration_ms", @floatFromInt(elapsed));
}

/// Process an HTTP/2 frame
fn processFrame(
    conn_context: anytype,
    h2_conn: *frames.Connection,
    frame: frames.Frame,
) !void {
    const logger = std.log.scoped(.http2_frame);

    switch (frame.header.type) {
        .HEADERS => {
            logger.debug("Received HEADERS frame for stream {d}", .{frame.header.stream_id});
            try processHeadersFrame(conn_context, h2_conn, frame);
        },
        .DATA => {
            logger.debug("Received DATA frame for stream {d}", .{frame.header.stream_id});
            try processDataFrame(conn_context, h2_conn, frame);
        },
        .SETTINGS => {
            logger.debug("Received SETTINGS frame", .{});
            try processSettingsFrame(h2_conn, frame);
        },
        .PING => {
            logger.debug("Received PING frame", .{});
            try processPingFrame(h2_conn, frame);
        },
        .GOAWAY => {
            logger.debug("Received GOAWAY frame", .{});
            return error.ConnectionClosed;
        },
        .WINDOW_UPDATE => {
            logger.debug("Received WINDOW_UPDATE frame", .{});
            // Handle window update
        },
        .RST_STREAM => {
            logger.debug("Received RST_STREAM frame for stream {d}", .{frame.header.stream_id});
            // Handle stream reset
        },
        .PRIORITY => {
            logger.debug("Received PRIORITY frame", .{});
            // Handle priority
        },
        .PUSH_PROMISE => {
            logger.debug("Received PUSH_PROMISE frame", .{});
            // Handle push promise
        },
        .CONTINUATION => {
            logger.debug("Received CONTINUATION frame", .{});
            // Handle continuation
        },
        _ => {
            logger.warn("Received unknown frame type: {}", .{@intFromEnum(frame.header.type)});
        },
    }
}

/// Process a HEADERS frame
fn processHeadersFrame(
    conn_context: anytype,
    h2_conn: *frames.Connection,
    frame: frames.Frame,
) !void {
    // Parse headers
    const headers = try frames.parseHeaders(
        conn_context.allocator,
        frame.payload,
    );
    defer {
        for (headers) |header| {
            conn_context.allocator.free(header.name);
            conn_context.allocator.free(header.value);
        }
        conn_context.allocator.free(headers);
    }

    // Extract method, path, etc.
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
        // Send protocol error
        try h2_conn.sendRstStream(frame.header.stream_id, .PROTOCOL_ERROR);
        return;
    }

    // Find a matching route
    const route = try conn_context.router.findRoute(path.?, method.?);
    if (route == null) {
        // Send 404 response
        try sendNotFound(h2_conn, @as(u31, @truncate(frame.header.stream_id)));
        return;
    }

    // Create a stream for this request
    var stream = try streams.Stream.init(
        conn_context.allocator,
        @as(u31, @truncate(frame.header.stream_id)),
        h2_conn,
    );
    defer stream.deinit();

    // Apply middleware
    var middleware_context = try createMiddlewareContext(
        conn_context,
        headers,
        route.?,
    );
    defer middleware_context.deinit();

    const middleware_result = try conn_context.router.applyMiddleware(&middleware_context);
    if (!middleware_result.success) {
        try sendMiddlewareError(h2_conn, @as(u31, @truncate(frame.header.stream_id)), middleware_result);
        return;
    }

    // Proxy the request to the upstream server
    try proxyRequest(conn_context, &stream, headers, route.?);
}

/// Process a DATA frame
fn processDataFrame(
    conn_context: anytype,
    h2_conn: *frames.Connection,
    frame: frames.Frame,
) !void {
    _ = conn_context;
    _ = h2_conn;
    _ = frame;
    return error.NotImplemented;
}

/// Process a SETTINGS frame
fn processSettingsFrame(
    h2_conn: *frames.Connection,
    frame: frames.Frame,
) !void {
    // ACK the SETTINGS frame
    try h2_conn.sendSettingsAck();

    // Apply settings
    if (frame.payload.len > 0) {
        const settings = try frames.parseSettings(frame.payload);
        h2_conn.applySettings(settings);
    }
}

/// Process a PING frame
fn processPingFrame(
    h2_conn: *frames.Connection,
    frame: frames.Frame,
) !void {
    // Send PING ACK with the same payload
    try h2_conn.sendPingAck(frame.payload);
}

/// Send a 404 Not Found response
fn sendNotFound(
    h2_conn: *frames.Connection,
    stream_id: u31,
) !void {
    // Send headers
    const headers = [_]frames.Header{
        .{ .name = ":status", .value = "404" },
        .{ .name = "content-type", .value = "text/plain" },
        .{ .name = "content-length", .value = "9" },
    };

    try h2_conn.sendHeaders(stream_id, headers[0..], false);

    // Send data
    try h2_conn.sendData(stream_id, "Not Found", true);
}

/// Send a middleware error response
fn sendMiddlewareError(
    h2_conn: *frames.Connection,
    stream_id: u31,
    middleware_result: anytype,
) !void {
    const status = switch (middleware_result.status_code) {
        401 => "401",
        403 => "403",
        429 => "429",
        else => "400",
    };

    // Send headers
    const headers = [_]frames.Header{
        .{ .name = ":status", .value = status },
        .{ .name = "content-type", .value = "text/plain" },
        .{ .name = "content-length", .value = try std.fmt.allocPrint(h2_conn.allocator, "{d}", .{middleware_result.error_message.len}) },
    };

    try h2_conn.sendHeaders(stream_id, headers[0..], false);

    // Send data
    try h2_conn.sendData(stream_id, middleware_result.error_message, true);
}

/// Create middleware context for the request
fn createMiddlewareContext(
    conn_context: anytype,
    headers: []const frames.Header,
    route: anytype,
) !@import("../../middleware/types.zig").Context {
    // Implementation depends on middleware types
    _ = conn_context;
    _ = headers;
    _ = route;
    return error.NotImplemented;
}

/// Proxy the request to the upstream server
fn proxyRequest(
    conn_context: anytype,
    stream: *streams.Stream,
    headers: []const frames.Header,
    route: anytype,
) !void {
    _ = conn_context;
    _ = stream;
    _ = headers;
    _ = route;
    return error.NotImplemented;
}
