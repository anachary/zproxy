const std = @import("std");
const logger = @import("../utils/logger.zig");

/// Upstream protocol
pub const UpstreamProtocol = enum {
    http,
    https,
};

/// Upstream information
pub const UpstreamInfo = struct {
    protocol: UpstreamProtocol,
    host: []const u8,
    port: u16,
    path: []const u8,
    
    pub fn deinit(self: *const UpstreamInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.host);
        allocator.free(self.path);
    }
};

/// Parse an upstream URL
pub fn parseUpstreamUrl(allocator: std.mem.Allocator, url: []const u8) !UpstreamInfo {
    // Parse URL
    var uri = try std.Uri.parse(url);
    
    // Determine protocol
    var protocol: UpstreamProtocol = undefined;
    if (std.mem.eql(u8, uri.scheme, "http")) {
        protocol = .http;
    } else if (std.mem.eql(u8, uri.scheme, "https")) {
        protocol = .https;
    } else {
        logger.err("Unsupported protocol: {s}", .{uri.scheme});
        return error.UnsupportedProtocol;
    }
    
    // Determine port
    const port = uri.port orelse switch (protocol) {
        .http => 80,
        .https => 443,
    };
    
    // Extract host and path
    const host = try allocator.dupe(u8, uri.host.?);
    const path = try allocator.dupe(u8, if (uri.path.len > 0) uri.path else "/");
    
    return UpstreamInfo{
        .protocol = protocol,
        .host = host,
        .port = port,
        .path = path,
    };
}

test "Upstream - Parse URL" {
    const testing = std.testing;
    
    // Test HTTP URL
    const http_url = "http://example.com/api";
    const http_info = try parseUpstreamUrl(testing.allocator, http_url);
    defer http_info.deinit(testing.allocator);
    
    try testing.expectEqual(UpstreamProtocol.http, http_info.protocol);
    try testing.expectEqualStrings("example.com", http_info.host);
    try testing.expectEqual(@as(u16, 80), http_info.port);
    try testing.expectEqualStrings("/api", http_info.path);
    
    // Test HTTPS URL with port
    const https_url = "https://secure.example.com:8443/api/users";
    const https_info = try parseUpstreamUrl(testing.allocator, https_url);
    defer https_info.deinit(testing.allocator);
    
    try testing.expectEqual(UpstreamProtocol.https, https_info.protocol);
    try testing.expectEqualStrings("secure.example.com", https_info.host);
    try testing.expectEqual(@as(u16, 8443), https_info.port);
    try testing.expectEqualStrings("/api/users", https_info.path);
    
    // Test URL without path
    const no_path_url = "http://example.com";
    const no_path_info = try parseUpstreamUrl(testing.allocator, no_path_url);
    defer no_path_info.deinit(testing.allocator);
    
    try testing.expectEqual(UpstreamProtocol.http, no_path_info.protocol);
    try testing.expectEqualStrings("example.com", no_path_info.host);
    try testing.expectEqual(@as(u16, 80), no_path_info.port);
    try testing.expectEqualStrings("/", no_path_info.path);
}
