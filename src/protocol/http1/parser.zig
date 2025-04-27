const std = @import("std");

/// HTTP request representation
pub const Request = struct {
    allocator: std.mem.Allocator,
    method: []const u8,
    path: []const u8,
    version: []const u8,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    
    /// Initialize a new Request
    pub fn init(allocator: std.mem.Allocator) !Request {
        return Request{
            .allocator = allocator,
            .method = "",
            .path = "",
            .version = "",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *Request) void {
        self.allocator.free(self.method);
        self.allocator.free(self.path);
        self.allocator.free(self.version);
        
        var header_it = self.headers.iterator();
        while (header_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        
        if (self.body) |body| {
            self.allocator.free(body);
        }
    }
};

/// Parse an HTTP request from a buffer
pub fn parseRequest(allocator: std.mem.Allocator, buffer: []const u8) !Request {
    var request = try Request.init(allocator);
    errdefer request.deinit();
    
    // Split the buffer into lines
    var lines = std.mem.split(u8, buffer, "\r\n");
    
    // Parse the request line
    const request_line = lines.next() orelse return error.InvalidRequest;
    try parseRequestLine(allocator, request_line, &request);
    
    // Parse headers
    while (lines.next()) |line| {
        if (line.len == 0) {
            // Empty line indicates the end of headers
            break;
        }
        
        try parseHeader(allocator, line, &request);
    }
    
    // Parse body if present
    if (request.headers.get("Content-Length")) |content_length_str| {
        const content_length = try std.fmt.parseInt(usize, content_length_str, 10);
        if (content_length > 0) {
            // Find the body in the buffer
            const headers_end = std.mem.indexOf(u8, buffer, "\r\n\r\n") orelse return error.InvalidRequest;
            const body_start = headers_end + 4;
            
            if (body_start + content_length <= buffer.len) {
                request.body = try allocator.dupe(u8, buffer[body_start .. body_start + content_length]);
            }
        }
    }
    
    return request;
}

/// Parse the request line (e.g., "GET /path HTTP/1.1")
fn parseRequestLine(
    allocator: std.mem.Allocator,
    line: []const u8,
    request: *Request,
) !void {
    var parts = std.mem.tokenize(u8, line, " ");
    
    const method = parts.next() orelse return error.InvalidRequestLine;
    request.method = try allocator.dupe(u8, method);
    
    const path = parts.next() orelse return error.InvalidRequestLine;
    request.path = try allocator.dupe(u8, path);
    
    const version = parts.next() orelse return error.InvalidRequestLine;
    request.version = try allocator.dupe(u8, version);
}

/// Parse a header line (e.g., "Host: example.com")
fn parseHeader(
    allocator: std.mem.Allocator,
    line: []const u8,
    request: *Request,
) !void {
    const colon_pos = std.mem.indexOf(u8, line, ":") orelse return error.InvalidHeader;
    
    const name = std.mem.trim(u8, line[0..colon_pos], " ");
    const value = std.mem.trim(u8, line[colon_pos + 1 ..], " ");
    
    const name_dup = try allocator.dupe(u8, name);
    errdefer allocator.free(name_dup);
    
    const value_dup = try allocator.dupe(u8, value);
    errdefer allocator.free(value_dup);
    
    try request.headers.put(name_dup, value_dup);
}

// Tests
test "Parse simple HTTP request" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const request_text =
        \\GET /index.html HTTP/1.1
        \\Host: example.com
        \\User-Agent: Test
        \\
        \\
    ;
    
    var request = try parseRequest(allocator, request_text);
    defer request.deinit();
    
    try testing.expectEqualStrings("GET", request.method);
    try testing.expectEqualStrings("/index.html", request.path);
    try testing.expectEqualStrings("HTTP/1.1", request.version);
    try testing.expectEqualStrings("example.com", request.headers.get("Host").?);
    try testing.expectEqualStrings("Test", request.headers.get("User-Agent").?);
    try testing.expect(request.body == null);
}

test "Parse HTTP request with body" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    const request_text =
        \\POST /submit HTTP/1.1
        \\Host: example.com
        \\Content-Type: application/json
        \\Content-Length: 13
        \\
        \\{"key":"value"}
    ;
    
    var request = try parseRequest(allocator, request_text);
    defer request.deinit();
    
    try testing.expectEqualStrings("POST", request.method);
    try testing.expectEqualStrings("/submit", request.path);
    try testing.expectEqualStrings("HTTP/1.1", request.version);
    try testing.expectEqualStrings("example.com", request.headers.get("Host").?);
    try testing.expectEqualStrings("application/json", request.headers.get("Content-Type").?);
    try testing.expectEqualStrings("13", request.headers.get("Content-Length").?);
    try testing.expectEqualStrings("{\"key\":\"value\"}", request.body.?);
}
