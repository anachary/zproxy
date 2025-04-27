const std = @import("std");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    // We're not using the allocator in this simple example
    _ = gpa.allocator();

    // Create a simple HTTP server
    const address = try std.net.Address.parseIp("127.0.0.1", 8080);
    var server = std.net.StreamServer.init(.{
        .reuse_address = true,
    });
    defer server.deinit();

    try server.listen(address);
    std.debug.print("ZProxy server listening on 127.0.0.1:8080\n", .{});
    std.debug.print("Healthcheck endpoint available at: http://127.0.0.1:8080/health\n", .{});

    // Accept connections
    while (true) {
        const connection = server.accept() catch |err| {
            std.debug.print("Error accepting connection: {}\n", .{err});
            continue;
        };

        // Handle the connection in a separate thread
        const thread = try std.Thread.spawn(.{}, handleConnection, .{connection});
        thread.detach();
    }
}

fn handleConnection(connection: std.net.StreamServer.Connection) !void {
    defer connection.stream.close();

    var buffer: [4096]u8 = undefined;
    const bytes_read = try connection.stream.read(&buffer);

    if (bytes_read == 0) return;

    // Parse the request to get the path
    const request = parseRequest(buffer[0..bytes_read]);
    std.debug.print("Received request: {s} {s}\n", .{ request.method, request.path });

    // Handle different paths
    if (std.mem.eql(u8, request.path, "/health")) {
        // Health check endpoint
        try sendHealthCheckResponse(connection);
    } else if (std.mem.eql(u8, request.path, "/")) {
        // Root endpoint
        try sendRootResponse(connection);
    } else {
        // Not found
        try sendNotFoundResponse(connection);
    }
}

const Request = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
};

fn parseRequest(request_data: []const u8) Request {
    var result = Request{
        .method = "",
        .path = "",
        .headers = std.StringHashMap([]const u8).init(std.heap.page_allocator),
    };

    // Find the first line
    var lines = std.mem.split(u8, request_data, "\r\n");
    if (lines.next()) |first_line| {
        var parts = std.mem.split(u8, first_line, " ");
        if (parts.next()) |method| {
            result.method = method;
        }
        if (parts.next()) |path| {
            result.path = path;
        }
    }

    return result;
}

fn sendHealthCheckResponse(connection: std.net.StreamServer.Connection) !void {
    const timestamp = std.time.timestamp();

    // Create JSON response with health status and timestamp
    var json_buffer: [256]u8 = undefined;
    const json = try std.fmt.bufPrint(&json_buffer,
        \\{{
        \\  "status": "healthy",
        \\  "timestamp": {d},
        \\  "version": "1.0.0",
        \\  "uptime": {d}
        \\}}
    , .{ timestamp, 3600 }); // Hardcoded uptime for now

    // Create HTTP response
    var response_buffer: [512]u8 = undefined;
    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: {d}\r\n" ++
        "\r\n" ++
        "{s}", .{ json.len, json });

    _ = try connection.stream.write(response);
}

fn sendRootResponse(connection: std.net.StreamServer.Connection) !void {
    const body =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>ZProxy Server</title>
        \\  <style>
        \\    body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        \\    h1 { color: #333; }
        \\    .container { max-width: 800px; margin: 0 auto; }
        \\    .info { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        \\    .endpoints { margin-top: 20px; }
        \\    .endpoint { margin-bottom: 10px; }
        \\  </style>
        \\</head>
        \\<body>
        \\  <div class="container">
        \\    <h1>ZProxy Server</h1>
        \\    <div class="info">
        \\      <p>Welcome to the ZProxy server. This is a high-performance API gateway written in Zig.</p>
        \\    </div>
        \\    <div class="endpoints">
        \\      <h2>Available Endpoints:</h2>
        \\      <div class="endpoint">
        \\        <strong>GET /health</strong> - Health check endpoint
        \\      </div>
        \\    </div>
        \\  </div>
        \\</body>
        \\</html>
        \\
    ;

    // Create HTTP response
    var response_buffer: [2048]u8 = undefined;
    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/html\r\n" ++
        "Content-Length: {d}\r\n" ++
        "\r\n" ++
        "{s}", .{ body.len, body });

    _ = try connection.stream.write(response);
}

fn sendNotFoundResponse(connection: std.net.StreamServer.Connection) !void {
    const body = "404 Not Found";

    // Create HTTP response
    var response_buffer: [256]u8 = undefined;
    const response = try std.fmt.bufPrint(&response_buffer, "HTTP/1.1 404 Not Found\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Content-Length: {d}\r\n" ++
        "\r\n" ++
        "{s}", .{ body.len, body });

    _ = try connection.stream.write(response);
}
