const std = @import("std");
const route = @import("route.zig");
const logger = @import("../utils/logger.zig");

/// Check if a route path matches a request path
pub fn matchPath(route_path: []const u8, request_path: []const u8) bool {
    // Exact match
    if (std.mem.eql(u8, route_path, request_path)) {
        return true;
    }
    
    // Wildcard match
    if (std.mem.endsWith(u8, route_path, "/*")) {
        const prefix = route_path[0 .. route_path.len - 2];
        return std.mem.startsWith(u8, request_path, prefix);
    }
    
    // Parameter match (simplified)
    if (std.mem.indexOf(u8, route_path, ":") != null) {
        // Split the paths into segments
        var route_segments = std.mem.split(u8, route_path, "/");
        var request_segments = std.mem.split(u8, request_path, "/");
        
        // Check each segment
        while (true) {
            const route_segment = route_segments.next();
            const request_segment = request_segments.next();
            
            // If either path ends, they both must end for a match
            if (route_segment == null or request_segment == null) {
                return route_segment == null and request_segment == null;
            }
            
            // Parameter segment
            if (std.mem.startsWith(u8, route_segment.?, ":")) {
                // Parameter matches any value
                continue;
            }
            
            // Regular segment must match exactly
            if (!std.mem.eql(u8, route_segment.?, request_segment.?)) {
                return false;
            }
        }
    }
    
    return false;
}

/// Match a path and extract parameters
pub fn matchPathWithParams(allocator: std.mem.Allocator, route_path: []const u8, request_path: []const u8) !?[]route.RouteParam {
    // Exact match (no parameters)
    if (std.mem.eql(u8, route_path, request_path)) {
        return &[_]route.RouteParam{};
    }
    
    // Wildcard match
    if (std.mem.endsWith(u8, route_path, "/*")) {
        const prefix = route_path[0 .. route_path.len - 2];
        if (std.mem.startsWith(u8, request_path, prefix)) {
            // Extract the wildcard value
            const wildcard_value = request_path[prefix.len..];
            
            // Create a parameter
            var params = try allocator.alloc(route.RouteParam, 1);
            params[0] = route.RouteParam{
                .name = try allocator.dupe(u8, "*"),
                .value = try allocator.dupe(u8, wildcard_value),
            };
            
            return params;
        }
        
        return null;
    }
    
    // Parameter match
    if (std.mem.indexOf(u8, route_path, ":") != null) {
        // Split the paths into segments
        var route_segments = std.mem.split(u8, route_path, "/");
        var request_segments = std.mem.split(u8, request_path, "/");
        
        // Collect parameters
        var params = std.ArrayList(route.RouteParam).init(allocator);
        defer {
            // Free parameters if we don't return them
            if (!matchPath(route_path, request_path)) {
                for (params.items) |param| {
                    allocator.free(param.name);
                    allocator.free(param.value);
                }
                params.deinit();
            }
        }
        
        // Check each segment
        while (true) {
            const route_segment = route_segments.next();
            const request_segment = request_segments.next();
            
            // If either path ends, they both must end for a match
            if (route_segment == null or request_segment == null) {
                if (route_segment == null and request_segment == null) {
                    return params.toOwnedSlice();
                }
                
                return null;
            }
            
            // Parameter segment
            if (std.mem.startsWith(u8, route_segment.?, ":")) {
                // Extract parameter name (without the colon)
                const param_name = route_segment.?[1..];
                
                // Create a parameter
                try params.append(route.RouteParam{
                    .name = try allocator.dupe(u8, param_name),
                    .value = try allocator.dupe(u8, request_segment.?),
                });
                
                continue;
            }
            
            // Regular segment must match exactly
            if (!std.mem.eql(u8, route_segment.?, request_segment.?)) {
                return null;
            }
        }
    }
    
    return null;
}
