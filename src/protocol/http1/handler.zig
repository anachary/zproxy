const std = @import("std");
const parser = @import("parser.zig");

/// Handle an HTTP/1.x connection
pub fn handle(conn_context: anytype) !void {
    const logger = std.log.scoped(.http1_handler);
    logger.debug("Handling HTTP/1.x connection", .{});

    // Parse the HTTP request
    var request = try parser.parseRequest(
        conn_context.allocator,
        conn_context.buffer,
    );
    defer request.deinit();

    // Find a matching route
    const route = try conn_context.router.findRoute(request.path, request.method);
    if (route == null) {
        logger.debug("No route found for {s} {s}", .{ request.method, request.path });
        try sendNotFound(conn_context);
        return;
    }

    // Apply middleware
    var middleware_context = try createMiddlewareContext(
        conn_context,
        request,
        route.?,
    );
    defer middleware_context.deinit();

    const middleware_result = try conn_context.router.applyMiddleware(&middleware_context);
    if (!middleware_result.success) {
        logger.info("Middleware rejected request: {s}", .{middleware_result.error_message});
        try sendMiddlewareError(conn_context, middleware_result);
        return;
    }

    // Proxy the request to the upstream server
    try proxyRequest(conn_context, request, route.?);
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
    conn_context: anytype,
    request: parser.Request,
    route: anytype,
) !@import("../../middleware/types.zig").Context {
    const types = @import("../../middleware/types.zig");

    // Create a request object that matches the HttpRequest interface
    var http_request = try conn_context.allocator.create(types.HttpRequest);
    http_request.* = types.HttpRequest{
        .method = request.method,
        .path = request.path,
        .headers = request.headers,
    };

    // Create a route object that matches the Route interface
    var route_obj = try conn_context.allocator.create(types.Route);
    route_obj.* = types.Route{
        .path = route.path_pattern,
        .upstream = route.upstream_url,
    };

    return try types.Context.init(conn_context.allocator, http_request, route_obj);
}

/// Proxy the request to the upstream server
fn proxyRequest(
    conn_context: anytype,
    request: parser.Request,
    route: anytype,
) !void {
    _ = request;
    const logger = std.log.scoped(.http1_proxy);
    logger.debug("Proxying request to {s}", .{route.upstream_url});

    // Parse the upstream URL
    var upstream_url = try std.Uri.parse(route.upstream_url);

    // For demonstration purposes, let's use a simple mock response
    // In a real implementation, we would connect to the upstream server
    logger.info("Would connect to {s}:{d}", .{
        upstream_url.host orelse "unknown",
        upstream_url.port orelse 80,
    });

    // Send a mock response directly to the client
    const mock_response =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Content-Length: 59\r\n" ++
        "\r\n" ++
        "This is a mock response from ZProxy. Upstream URL: localhost:3000";

    _ = try conn_context.connection.stream.write(mock_response);

    // In a real implementation, we would do something like this:
    // var upstream_conn = try std.net.tcpConnectToAddress(upstream_address);
    // defer upstream_conn.close();
    // try forwardRequest(conn_context, upstream_conn, request, route);
    // try forwardResponse(conn_context, upstream_conn);
}

/// Forward the request to the upstream server
fn forwardRequest(
    conn_context: anytype,
    upstream_conn: std.net.Stream,
    request: parser.Request,
    route: anytype,
) !void {
    _ = route;
    // Build the request line
    var request_line = try std.fmt.allocPrint(
        conn_context.allocator,
        "{s} {s} {s}\r\n",
        .{ request.method, request.path, request.version },
    );
    defer conn_context.allocator.free(request_line);

    // Send the request line
    _ = try upstream_conn.write(request_line);

    // Send the headers
    var header_it = request.headers.iterator();
    while (header_it.next()) |entry| {
        const header_line = try std.fmt.allocPrint(
            conn_context.allocator,
            "{s}: {s}\r\n",
            .{ entry.key_ptr.*, entry.value_ptr.* },
        );
        defer conn_context.allocator.free(header_line);

        _ = try upstream_conn.write(header_line);
    }

    // End of headers
    _ = try upstream_conn.write("\r\n");

    // Send the body if present
    if (request.body) |body| {
        _ = try upstream_conn.write(body);
    }
}

/// Forward the response from the upstream server back to the client
fn forwardResponse(
    conn_context: anytype,
    upstream_conn: std.net.Stream,
) !void {
    // Read the response from the upstream server
    var buffer = try conn_context.allocator.alloc(u8, 8192);
    defer conn_context.allocator.free(buffer);

    // Read in chunks and forward to the client
    while (true) {
        const bytes_read = try upstream_conn.read(buffer);
        if (bytes_read == 0) {
            // End of response
            break;
        }

        // Forward the chunk to the client
        _ = try conn_context.connection.stream.write(buffer[0..bytes_read]);
    }
}
