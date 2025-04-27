const std = @import("std");
const parser = @import("parser.zig");
const utils = @import("../../utils/allocator.zig");

/// Handle an HTTP/1.x connection
pub fn handle(conn_context: anytype) !void {
    const logger = std.log.scoped(.http1_handler);
    logger.debug("Handling HTTP/1.x connection", .{});

    // Use an arena allocator for the request lifetime to improve performance
    var arena = utils.ArenaAllocator.init(conn_context.allocator);
    defer arena.deinit();
    const arena_allocator = arena.getAllocator();

    // Start timer for metrics and store in context for later use
    conn_context.timer = utils.time.Timer.start();

    // Parse the HTTP request
    var request = try parser.parseRequest(
        arena_allocator, // Use arena allocator for request parsing
        conn_context.buffer,
    );
    // No need for defer request.deinit() as arena will free everything

    // Find a matching route - use fast path for common routes
    const route = try conn_context.router.findRoute(request.path, request.method);
    if (route == null) {
        logger.debug("No route found for {s} {s}", .{ request.method, request.path });
        try sendNotFound(conn_context);

        // Record metrics for 404
        try conn_context.metrics_collector.incrementCounter("http.status.404", 1);
        return;
    }

    // Apply middleware
    var middleware_context = try createMiddlewareContext(
        arena_allocator, // Use arena allocator for middleware context
        conn_context,
        request,
        route.?,
    );
    // No need for defer middleware_context.deinit() as arena will free everything

    const middleware_result = try conn_context.router.applyMiddleware(&middleware_context);
    if (!middleware_result.success) {
        logger.info("Middleware rejected request: {s}", .{middleware_result.error_message});
        try sendMiddlewareError(conn_context, middleware_result);

        // Record metrics for middleware rejection
        try conn_context.metrics_collector.incrementCounter("http.middleware.rejected", 1);
        return;
    }

    // Proxy the request to the upstream server
    try proxyRequest(conn_context, arena_allocator, request, route.?);

    // Record metrics
    const elapsed = conn_context.timer.elapsedMillis();
    try conn_context.metrics_collector.recordHistogram("http.request_duration_ms", @floatFromInt(elapsed));
}

/// Send a 404 Not Found response
fn sendNotFound(conn_context: anytype) !void {
    const response =
        \\HTTP/1.1 404 Not Found
        \\Content-Type: text/plain
        \\Content-Length: 9
        \\
        \\Not Found
    ;

    _ = try conn_context.connection.stream.write(response);
}

/// Send a middleware error response
fn sendMiddlewareError(conn_context: anytype, middleware_result: anytype) !void {
    const status_line = switch (middleware_result.status_code) {
        401 => "HTTP/1.1 401 Unauthorized",
        403 => "HTTP/1.1 403 Forbidden",
        429 => "HTTP/1.1 429 Too Many Requests",
        else => "HTTP/1.1 400 Bad Request",
    };

    const response = try std.fmt.allocPrint(
        conn_context.allocator,
        "{s}\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}",
        .{
            status_line,
            middleware_result.error_message.len,
            middleware_result.error_message,
        },
    );
    defer conn_context.allocator.free(response);

    _ = try conn_context.connection.stream.write(response);
}

/// Create middleware context for the request
fn createMiddlewareContext(
    allocator: std.mem.Allocator,
    conn_context: anytype,
    request: parser.Request,
    route: anytype,
) !@import("../../middleware/types.zig").Context {
    _ = conn_context;
    const types = @import("../../middleware/types.zig");

    // Create a request object that matches the HttpRequest interface
    var http_request = try allocator.create(types.HttpRequest);
    http_request.* = types.HttpRequest{
        .method = request.method,
        .path = request.path,
        .headers = request.headers,
    };

    // Create a route object that matches the Route interface
    var route_obj = try allocator.create(types.Route);
    route_obj.* = types.Route{
        .path = route.path_pattern,
        .upstream = route.upstream_url,
    };

    return try types.Context.init(allocator, http_request, route_obj);
}

/// Proxy the request to the upstream server
fn proxyRequest(
    conn_context: anytype,
    allocator: std.mem.Allocator,
    request: parser.Request,
    route: anytype,
) !void {
    const logger = std.log.scoped(.http1_proxy);
    logger.debug("Proxying request to {s}", .{route.upstream_url});

    // Start timer for upstream request
    var timer = utils.time.Timer.start();

    // Get a connection from the pool
    var connection = try route.upstream_pool.getConnection();
    defer connection.release(); // Use the optimized release method

    // Forward the request to the upstream server
    try forwardRequest(conn_context, allocator, connection.stream, request, route);

    // Record upstream request time
    const upstream_req_time = timer.elapsedMillis();
    try conn_context.metrics_collector.recordHistogram("http.upstream_request_ms", @floatFromInt(upstream_req_time));

    // Forward the response back to the client
    try forwardResponse(conn_context, allocator, connection.stream);

    // Record total upstream time
    const total_upstream_time = timer.elapsedMillis();
    try conn_context.metrics_collector.recordHistogram("http.upstream_total_ms", @floatFromInt(total_upstream_time));

    // Record successful proxy
    try conn_context.metrics_collector.incrementCounter("http.proxy.success", 1);
}

/// Forward the request to the upstream server
fn forwardRequest(
    conn_context: anytype,
    allocator: std.mem.Allocator,
    upstream_conn: std.net.Stream,
    request: parser.Request,
    route: anytype,
) !void {
    _ = conn_context;
    _ = route;

    // Use a string builder for efficient request construction
    var builder = utils.buffer.StringBuilder.init(allocator);
    defer builder.deinit();

    // Build the request line
    try builder.appendFmt("{s} {s} {s}\r\n", .{ request.method, request.path, request.version });

    // Add headers
    var header_it = request.headers.iterator();
    while (header_it.next()) |entry| {
        try builder.appendFmt("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }

    // End of headers
    try builder.append("\r\n");

    // Write the request headers in a single operation
    _ = try upstream_conn.write(builder.string());

    // Send the body if present (zero-copy)
    if (request.body) |body| {
        _ = try upstream_conn.write(body);
    }
}

/// Forward the response from the upstream server back to the client
fn forwardResponse(
    conn_context: anytype,
    allocator: std.mem.Allocator,
    upstream_conn: std.net.Stream,
) !void {
    _ = allocator;

    // Set up socket options for optimal performance
    try upstream_conn.setNoDelay(true); // Disable Nagle's algorithm
    try conn_context.connection.stream.setNoDelay(true);

    // Set socket buffer sizes for better throughput
    try upstream_conn.setSocketOptInt(std.os.SOL.SOCKET, std.os.SO.RCVBUF, 262144); // 256KB receive buffer
    try conn_context.connection.stream.setSocketOptInt(std.os.SOL.SOCKET, std.os.SO.SNDBUF, 262144); // 256KB send buffer

    // Use vectored I/O if available
    if (@hasDecl(@TypeOf(conn_context), "getVectoredBuffer")) {
        // Get a vectored buffer from the connection context's pool
        var vectored_buffer = try conn_context.getVectoredBuffer();
        defer conn_context.returnVectoredBuffer(vectored_buffer);

        // Forward all data from upstream to client using vectored I/O
        const total_bytes = try vectored_buffer.forwardAll(upstream_conn, conn_context.connection.stream);

        // Record metrics
        try conn_context.metrics_collector.incrementCounter("http.bytes_transferred", total_bytes);
        try conn_context.metrics_collector.incrementCounter("http.vectored_io_used", 1);

        // Record throughput metrics (bytes per second)
        if (total_bytes > 0) {
            const elapsed_ms = conn_context.timer.elapsedMillis();
            if (elapsed_ms > 0) {
                const throughput = @as(f64, @floatFromInt(total_bytes)) / (@as(f64, @floatFromInt(elapsed_ms)) / 1000.0);
                try conn_context.metrics_collector.recordHistogram("http.throughput_bytes_per_second", throughput);

                // Log high throughput for debugging
                if (throughput > 100_000_000) { // 100 MB/s
                    const logger = std.log.scoped(.http1_proxy);
                    logger.info("High throughput (vectored): {d:.2} MB/s", .{throughput / 1_000_000});
                }
            }
        }
    } else {
        // Fall back to zero-copy buffer
        var zero_copy_buffer = try conn_context.getZeroCopyBuffer();
        defer conn_context.returnZeroCopyBuffer(zero_copy_buffer);

        // Forward all data from upstream to client
        const total_bytes = try zero_copy_buffer.forwardAll(upstream_conn, conn_context.connection.stream);

        // Record metrics
        try conn_context.metrics_collector.incrementCounter("http.bytes_transferred", total_bytes);

        // Record throughput metrics (bytes per second)
        if (total_bytes > 0) {
            const elapsed_ms = conn_context.timer.elapsedMillis();
            if (elapsed_ms > 0) {
                const throughput = @as(f64, @floatFromInt(total_bytes)) / (@as(f64, @floatFromInt(elapsed_ms)) / 1000.0);
                try conn_context.metrics_collector.recordHistogram("http.throughput_bytes_per_second", throughput);

                // Log high throughput for debugging
                if (throughput > 100_000_000) { // 100 MB/s
                    const logger = std.log.scoped(.http1_proxy);
                    logger.info("High throughput (zero-copy): {d:.2} MB/s", .{throughput / 1_000_000});
                }
            }
        }
    }
}
