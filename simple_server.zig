const std = @import("std");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    // We're not using the allocator in this simple example
    _ = gpa.allocator();

    // Create a simple HTTP server
    const address = try std.net.Address.parseIp("127.0.0.1", 8080);
    var server = std.net.StreamServer.init(.{});
    defer server.deinit();

    try server.listen(address);
    std.debug.print("Server listening on 127.0.0.1:8080\n", .{});

    // Accept connections
    while (true) {
        const connection = server.accept() catch |err| {
            std.debug.print("Error accepting connection: {}\n", .{err});
            continue;
        };
        defer connection.stream.close();

        std.debug.print("New connection from {}\n", .{connection.address});

        // Handle the connection
        handleConnection(connection) catch |err| {
            std.debug.print("Error handling connection: {}\n", .{err});
        };
    }
}

fn handleConnection(connection: std.net.StreamServer.Connection) !void {
    var buffer: [1024]u8 = undefined;
    const bytes_read = try connection.stream.read(&buffer);

    if (bytes_read == 0) return;

    // Print the request
    std.debug.print("Received request:\n{s}\n", .{buffer[0..bytes_read]});

    // Send a simple response
    const response =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: text/plain\r\n" ++
        "Content-Length: 13\r\n" ++
        "\r\n" ++
        "Hello, World!";

    _ = try connection.stream.write(response);
}
