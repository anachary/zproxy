const std = @import("std");
const logger = @import("../utils/logger.zig");

/// HTTP/1.1 request
pub const Http1Request = struct {
    method: []const u8,
    path: []const u8,
    version: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    client_addr: std.net.Address,
    
    /// Initialize a new HTTP/1.1 request
    pub fn init(allocator: std.mem.Allocator, client_addr: std.net.Address) !Http1Request {
        return Http1Request{
            .method = "",
            .path = "",
            .version = "",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .client_addr = client_addr,
        };
    }
    
    /// Clean up request resources
    pub fn deinit(self: *Http1Request) void {
        self.headers.deinit();
    }
};

/// HTTP/1.1 response
pub const Http1Response = struct {
    status_code: u16,
    status_text: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    
    /// Initialize a new HTTP/1.1 response
    pub fn init(allocator: std.mem.Allocator) !Http1Response {
        return Http1Response{
            .status_code = 200,
            .status_text = "OK",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
        };
    }
    
    /// Clean up response resources
    pub fn deinit(self: *Http1Response) void {
        self.headers.deinit();
    }
    
    /// Write the response to a stream
    pub fn write(self: *const Http1Response, stream: std.net.Stream) !void {
        // Write status line
        try stream.writer().print("HTTP/1.1 {d} {s}\r\n", .{ self.status_code, self.status_text });
        
        // Write headers
        var headers_it = self.headers.iterator();
        while (headers_it.next()) |entry| {
            try stream.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }
        
        // Write content length if not already set
        if (!self.headers.contains("Content-Length")) {
            try stream.writer().print("Content-Length: {d}\r\n", .{self.body.len});
        }
        
        // Write connection close if not already set
        if (!self.headers.contains("Connection")) {
            try stream.writer().print("Connection: close\r\n", .{});
        }
        
        // Write empty line to separate headers from body
        try stream.writer().writeAll("\r\n");
        
        // Write body
        if (self.body.len > 0) {
            try stream.writer().writeAll(self.body);
        }
    }
};

/// Parse an HTTP/1.1 request from a buffer
pub fn parseRequest(allocator: std.mem.Allocator, buffer: []const u8, client_addr: std.net.Address) !Http1Request {
    var request = try Http1Request.init(allocator, client_addr);
    errdefer request.deinit();
    
    // Find the end of the request line
    const request_line_end = std.mem.indexOf(u8, buffer, "\r\n") orelse return error.InvalidRequest;
    const request_line = buffer[0..request_line_end];
    
    // Parse the request line
    var request_line_it = std.mem.split(u8, request_line, " ");
    request.method = request_line_it.next() orelse return error.InvalidRequest;
    request.path = request_line_it.next() orelse return error.InvalidRequest;
    request.version = request_line_it.next() orelse return error.InvalidRequest;
    
    // Check HTTP version
    if (!std.mem.eql(u8, request.version, "HTTP/1.1") and !std.mem.eql(u8, request.version, "HTTP/1.0")) {
        return error.UnsupportedHttpVersion;
    }
    
    // Parse headers
    var headers_start = request_line_end + 2;
    var headers_end = std.mem.indexOf(u8, buffer[headers_start..], "\r\n\r\n") orelse return error.InvalidRequest;
    headers_end += headers_start;
    
    var header_start = headers_start;
    while (header_start < headers_end) {
        const header_end = std.mem.indexOf(u8, buffer[header_start..headers_end], "\r\n") orelse break;
        const header_line = buffer[header_start .. header_start + header_end];
        
        const colon_pos = std.mem.indexOf(u8, header_line, ":") orelse return error.InvalidHeader;
        const header_name = std.mem.trim(u8, header_line[0..colon_pos], " ");
        const header_value = std.mem.trim(u8, header_line[colon_pos + 1..], " ");
        
        try request.headers.put(try allocator.dupe(u8, header_name), try allocator.dupe(u8, header_value));
        
        header_start += header_end + 2;
    }
    
    // Parse body
    const body_start = headers_end + 4;
    if (body_start < buffer.len) {
        request.body = buffer[body_start..];
    }
    
    return request;
}

/// Create a simple response
pub fn createResponse(allocator: std.mem.Allocator, status_code: u16, status_text: []const u8, body: []const u8) !Http1Response {
    var response = try Http1Response.init(allocator);
    errdefer response.deinit();
    
    response.status_code = status_code;
    response.status_text = status_text;
    response.body = body;
    
    try response.headers.put("Content-Type", "text/plain");
    try response.headers.put("Server", "ZProxy");
    
    return response;
}

/// Handle an HTTP/1.1 request
pub fn handleRequest(allocator: std.mem.Allocator, stream: std.net.Stream, client_addr: std.net.Address) !void {
    // Read the request
    var buffer: [8192]u8 = undefined;
    const bytes_read = try stream.read(&buffer);
    
    if (bytes_read == 0) {
        logger.debug("Empty request from {}", .{client_addr});
        return;
    }
    
    // Parse the request
    var request = parseRequest(allocator, buffer[0..bytes_read], client_addr) catch |err| {
        logger.err("Error parsing request: {}", .{err});
        
        // Send error response
        var response = try createResponse(allocator, 400, "Bad Request", "Invalid HTTP request");
        defer response.deinit();
        
        try response.write(stream);
        return;
    };
    defer request.deinit();
    
    logger.debug("Received {s} request for {s} from {}", .{ request.method, request.path, client_addr });
    
    // Create a response (this would normally be handled by the router)
    var response = try createResponse(allocator, 200, "OK", "Hello from ZProxy!");
    defer response.deinit();
    
    // Send the response
    try response.write(stream);
}

test "HTTP/1.1 - Parse Request" {
    const testing = std.testing;
    
    const request_str =
        \\GET /index.html HTTP/1.1
        \\Host: example.com
        \\User-Agent: ZProxy Test
        \\Accept: */*
        \\
        \\
    ;
    
    const client_addr = try std.net.Address.parseIp("127.0.0.1", 12345);
    
    var request = try parseRequest(testing.allocator, request_str, client_addr);
    defer request.deinit();
    
    try testing.expectEqualStrings("GET", request.method);
    try testing.expectEqualStrings("/index.html", request.path);
    try testing.expectEqualStrings("HTTP/1.1", request.version);
    
    try testing.expectEqualStrings("example.com", request.headers.get("Host").?);
    try testing.expectEqualStrings("ZProxy Test", request.headers.get("User-Agent").?);
    try testing.expectEqualStrings("*/*", request.headers.get("Accept").?);
    
    try testing.expectEqualStrings("", request.body);
}

test "HTTP/1.1 - Create Response" {
    const testing = std.testing;
    
    var response = try createResponse(testing.allocator, 200, "OK", "Hello, World!");
    defer response.deinit();
    
    try testing.expectEqual(@as(u16, 200), response.status_code);
    try testing.expectEqualStrings("OK", response.status_text);
    try testing.expectEqualStrings("Hello, World!", response.body);
    
    try testing.expectEqualStrings("text/plain", response.headers.get("Content-Type").?);
    try testing.expectEqualStrings("ZProxy", response.headers.get("Server").?);
}
