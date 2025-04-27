const std = @import("std");

/// Pattern types for path matching
const PatternType = enum {
    literal,
    parameter,
    wildcard,
};

/// A segment in a path pattern
const PatternSegment = struct {
    type: PatternType,
    value: []const u8,
};

/// Path matcher for route matching
pub const PathMatcher = struct {
    allocator: std.mem.Allocator,
    pattern: []const u8,
    segments: []PatternSegment,
    
    /// Initialize a new PathMatcher
    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) !PathMatcher {
        // Parse the pattern into segments
        var segments_list = std.ArrayList(PatternSegment).init(allocator);
        defer segments_list.deinit();
        
        var path_parts = std.mem.split(u8, pattern, "/");
        while (path_parts.next()) |part| {
            if (part.len == 0) {
                continue;
            }
            
            if (std.mem.eql(u8, part, "*")) {
                // Wildcard segment
                try segments_list.append(PatternSegment{
                    .type = .wildcard,
                    .value = try allocator.dupe(u8, "*"),
                });
            } else if (part.len > 0 and part[0] == ':') {
                // Parameter segment
                try segments_list.append(PatternSegment{
                    .type = .parameter,
                    .value = try allocator.dupe(u8, part[1..]),
                });
            } else {
                // Literal segment
                try segments_list.append(PatternSegment{
                    .type = .literal,
                    .value = try allocator.dupe(u8, part),
                });
            }
        }
        
        return PathMatcher{
            .allocator = allocator,
            .pattern = try allocator.dupe(u8, pattern),
            .segments = try segments_list.toOwnedSlice(),
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *const PathMatcher) void {
        self.allocator.free(self.pattern);
        
        for (self.segments) |segment| {
            self.allocator.free(segment.value);
        }
        self.allocator.free(self.segments);
    }
    
    /// Check if a path matches this pattern
    pub fn matches(self: *const PathMatcher, path: []const u8) !bool {
        // Special case for root path
        if (std.mem.eql(u8, self.pattern, "/") and std.mem.eql(u8, path, "/")) {
            return true;
        }
        
        // Split the path into segments
        var path_segments = std.ArrayList([]const u8).init(self.allocator);
        defer path_segments.deinit();
        
        var path_parts = std.mem.split(u8, path, "/");
        while (path_parts.next()) |part| {
            if (part.len == 0) {
                continue;
            }
            
            try path_segments.append(part);
        }
        
        // Check if the number of segments matches
        // (unless we have a wildcard at the end)
        const has_trailing_wildcard = self.segments.len > 0 and 
                                     self.segments[self.segments.len - 1].type == .wildcard;
        
        if (!has_trailing_wildcard and path_segments.items.len != self.segments.len) {
            return false;
        }
        
        if (has_trailing_wildcard and path_segments.items.len < self.segments.len - 1) {
            return false;
        }
        
        // Match each segment
        for (self.segments, 0..) |segment, i| {
            switch (segment.type) {
                .literal => {
                    if (i >= path_segments.items.len or 
                        !std.mem.eql(u8, segment.value, path_segments.items[i])) {
                        return false;
                    }
                },
                .parameter => {
                    // Parameters match any segment
                    if (i >= path_segments.items.len) {
                        return false;
                    }
                },
                .wildcard => {
                    // Wildcard matches the rest of the path
                    return true;
                },
            }
        }
        
        return true;
    }
    
    /// Extract parameters from a path
    pub fn extractParams(self: *const PathMatcher, path: []const u8) !std.StringHashMap([]const u8) {
        var params = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            var it = params.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            params.deinit();
        }
        
        // Split the path into segments
        var path_segments = std.ArrayList([]const u8).init(self.allocator);
        defer path_segments.deinit();
        
        var path_parts = std.mem.split(u8, path, "/");
        while (path_parts.next()) |part| {
            if (part.len == 0) {
                continue;
            }
            
            try path_segments.append(part);
        }
        
        // Extract parameters
        for (self.segments, 0..) |segment, i| {
            if (segment.type == .parameter and i < path_segments.items.len) {
                const param_name = try self.allocator.dupe(u8, segment.value);
                const param_value = try self.allocator.dupe(u8, path_segments.items[i]);
                try params.put(param_name, param_value);
            }
        }
        
        return params;
    }
};

// Tests
test "Path matcher - literal path" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var matcher = try PathMatcher.init(allocator, "/api/users");
    defer matcher.deinit();
    
    try testing.expect(try matcher.matches("/api/users"));
    try testing.expect(!try matcher.matches("/api/products"));
    try testing.expect(!try matcher.matches("/api/users/123"));
}

test "Path matcher - parameter path" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var matcher = try PathMatcher.init(allocator, "/api/users/:id");
    defer matcher.deinit();
    
    try testing.expect(try matcher.matches("/api/users/123"));
    try testing.expect(try matcher.matches("/api/users/abc"));
    try testing.expect(!try matcher.matches("/api/users"));
    try testing.expect(!try matcher.matches("/api/users/123/profile"));
}

test "Path matcher - wildcard path" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var matcher = try PathMatcher.init(allocator, "/api/*");
    defer matcher.deinit();
    
    try testing.expect(try matcher.matches("/api/users"));
    try testing.expect(try matcher.matches("/api/products"));
    try testing.expect(try matcher.matches("/api/users/123"));
    try testing.expect(!try matcher.matches("/other/path"));
}

test "Path matcher - extract parameters" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var matcher = try PathMatcher.init(allocator, "/api/users/:id/posts/:post_id");
    defer matcher.deinit();
    
    var params = try matcher.extractParams("/api/users/123/posts/456");
    defer {
        var it = params.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        params.deinit();
    }
    
    try testing.expectEqualStrings("123", params.get("id").?);
    try testing.expectEqualStrings("456", params.get("post_id").?);
}
