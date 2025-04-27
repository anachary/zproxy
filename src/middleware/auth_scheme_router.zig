const std = @import("std");
const types = @import("types.zig");

/// Middleware that routes traffic based on the authentication scheme
pub const AuthSchemeRouterMiddleware = struct {
    allocator: std.mem.Allocator,
    route_map: std.StringHashMap([]const u8),
    default_upstream: []const u8,
    
    /// Configuration for the auth scheme router
    pub const Config = struct {
        routes: []const struct {
            scheme: []const u8,
            upstream: []const u8,
        },
        default_upstream: []const u8,
    };
    
    /// Initialize the middleware
    pub fn init(allocator: std.mem.Allocator, config: Config) !AuthSchemeRouterMiddleware {
        var route_map = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var it = route_map.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            route_map.deinit();
        }
        
        // Add routes from config
        for (config.routes) |route| {
            const scheme = try allocator.dupe(u8, route.scheme);
            errdefer allocator.free(scheme);
            
            const upstream = try allocator.dupe(u8, route.upstream);
            errdefer allocator.free(upstream);
            
            try route_map.put(scheme, upstream);
        }
        
        return AuthSchemeRouterMiddleware{
            .allocator = allocator,
            .route_map = route_map,
            .default_upstream = try allocator.dupe(u8, config.default_upstream),
        };
    }
    
    /// Process a request
    pub fn process(self: *AuthSchemeRouterMiddleware, context: *types.Context) !types.MiddlewareResult {
        // Get the Authorization header
        const auth_header = context.request.headers.get("Authorization");
        
        // Extract the auth scheme if the header exists
        var auth_scheme: []const u8 = "none";
        if (auth_header) |header| {
            const space_index = std.mem.indexOf(u8, header, " ");
            if (space_index) |index| {
                auth_scheme = header[0..index];
            }
        }
        
        // Log the auth scheme
        std.log.info("Auth scheme: {s}", .{auth_scheme});
        
        // Look up the upstream URL for this auth scheme
        var upstream_url: []const u8 = undefined;
        if (self.route_map.get(auth_scheme)) |url| {
            upstream_url = url;
            std.log.info("Routing to {s} based on auth scheme", .{upstream_url});
        } else {
            upstream_url = self.default_upstream;
            std.log.info("Using default upstream {s}", .{upstream_url});
        }
        
        // Modify the route's upstream URL
        const new_upstream = try self.allocator.dupe(u8, upstream_url);
        
        // Update the context with the new upstream
        context.route.upstream = new_upstream;
        
        // Allow the request to continue
        return types.MiddlewareResult{
            .success = true,
            .status_code = 200,
            .error_message = "",
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *AuthSchemeRouterMiddleware) void {
        var it = self.route_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.route_map.deinit();
        self.allocator.free(self.default_upstream);
    }
};

test "auth scheme router middleware" {
    const testing = std.testing;
    
    // Create configuration
    const config = AuthSchemeRouterMiddleware.Config{
        .routes = &[_]struct { scheme: []const u8, upstream: []const u8 }{
            .{ .scheme = "Bearer", .upstream = "https://www.google.com" },
            .{ .scheme = "ServiceKey", .upstream = "https://www.duckduckgo.com" },
        },
        .default_upstream = "https://www.example.com",
    };
    
    // Initialize the middleware
    var middleware = try AuthSchemeRouterMiddleware.init(testing.allocator, config);
    defer middleware.deinit();
    
    // Create headers with Bearer token
    var headers = std.StringHashMap([]const u8).init(testing.allocator);
    defer headers.deinit();
    try headers.put("Authorization", "Bearer token123");
    
    // Create request and route
    var request = types.Request{
        .method = "GET",
        .path = "/api/users",
        .headers = headers,
    };
    
    var route = types.Route{
        .path = "/api/users",
        .upstream = "http://original-upstream.com",
    };
    
    // Create context
    var context = types.Context{
        .allocator = testing.allocator,
        .request = &request,
        .route = &route,
    };
    
    // Process the request
    const result = try middleware.process(&context);
    
    // Verify the result
    try testing.expect(result.success);
    try testing.expectEqual(@as(u16, 200), result.status_code);
    try testing.expectEqualStrings("", result.error_message);
    
    // Verify the route was updated to Google
    try testing.expectEqualStrings("https://www.google.com", route.upstream);
    
    // Clean up
    testing.allocator.free(route.upstream);
}
