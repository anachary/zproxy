const std = @import("std");
const testing = std.testing;
const router = @import("router");

test "Router path matching" {
    const allocator = testing.allocator;
    
    // Create a path matcher
    var matcher = try router.matcher.PathMatcher.init(allocator, "/api/users/:id");
    defer matcher.deinit();
    
    // Test matching paths
    try testing.expect(try matcher.matches("/api/users/123"));
    try testing.expect(try matcher.matches("/api/users/abc"));
    try testing.expect(!try matcher.matches("/api/users"));
    try testing.expect(!try matcher.matches("/api/products/123"));
}

test "Router parameter extraction" {
    const allocator = testing.allocator;
    
    // Create a path matcher
    var matcher = try router.matcher.PathMatcher.init(allocator, "/api/users/:id/posts/:post_id");
    defer matcher.deinit();
    
    // Extract parameters
    var params = try matcher.extractParams("/api/users/123/posts/456");
    defer {
        var it = params.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        params.deinit();
    }
    
    // Verify parameters
    try testing.expectEqualStrings("123", params.get("id").?);
    try testing.expectEqualStrings("456", params.get("post_id").?);
}

test "Router route finding" {
    const allocator = testing.allocator;
    
    const TestRoute = struct {
        path: []const u8,
        upstream: []const u8,
        methods: []const []const u8,
        middleware: []const []const u8,
    };
    
    const routes = [_]TestRoute{
        .{
            .path = "/api/users",
            .upstream = "http://users-service:8080",
            .methods = &[_][]const u8{ "GET", "POST" },
            .middleware = &[_][]const u8{},
        },
        .{
            .path = "/api/products",
            .upstream = "http://products-service:8080",
            .methods = &[_][]const u8{ "GET" },
            .middleware = &[_][]const u8{},
        },
    };
    
    var router_instance = try router.Router.init(allocator, &routes);
    defer router_instance.deinit();
    
    // Find routes
    const users_route = try router_instance.findRoute("/api/users", "GET");
    try testing.expect(users_route != null);
    try testing.expectEqualStrings("/api/users", users_route.?.path_pattern);
    
    const products_route = try router_instance.findRoute("/api/products", "GET");
    try testing.expect(products_route != null);
    try testing.expectEqualStrings("/api/products", products_route.?.path_pattern);
    
    // Test method not allowed
    const users_delete = try router_instance.findRoute("/api/users", "DELETE");
    try testing.expect(users_delete == null);
    
    // Test path not found
    const not_found = try router_instance.findRoute("/api/orders", "GET");
    try testing.expect(not_found == null);
}
