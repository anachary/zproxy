const std = @import("std");
const testing = std.testing;
const middleware = @import("middleware");

test "Cache store" {
    const allocator = testing.allocator;
    
    // Create cache store
    var cache = try middleware.cache.store.CacheStore.init(allocator);
    defer cache.deinit();
    
    // Set a value
    try cache.set("key1", "value1", 60);
    
    // Get the value
    const value = try cache.get("key1");
    try testing.expect(value != null);
    try testing.expectEqualStrings("value1", value.?);
    
    // Get a non-existent value
    const missing = try cache.get("key2");
    try testing.expect(missing == null);
    
    // Remove a value
    cache.remove("key1");
    const removed = try cache.get("key1");
    try testing.expect(removed == null);
}

test "Cache middleware" {
    const allocator = testing.allocator;
    
    // Create cache middleware
    const TestConfig = struct {
        ttl_seconds: u32,
    };
    
    const config = TestConfig{
        .ttl_seconds = 60,
    };
    
    var cache_middleware = try middleware.cache.cache.CacheMiddleware.create(allocator, config);
    defer allocator.destroy(@ptrCast(cache_middleware));
    
    // Create mock context
    const TestRequest = struct {
        method: []const u8,
        path: []const u8,
        headers: std.StringHashMap([]const u8),
        
        pub fn init(allocator: std.mem.Allocator, method: []const u8, path: []const u8) !TestRequest {
            var headers = std.StringHashMap([]const u8).init(allocator);
            
            return TestRequest{
                .method = method,
                .path = path,
                .headers = headers,
            };
        }
        
        pub fn deinit(self: *TestRequest) void {
            var it = self.headers.iterator();
            while (it.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            self.headers.deinit();
        }
    };
    
    const TestRoute = struct {
        path: []const u8,
    };
    
    // Test GET request
    var get_request = try TestRequest.init(allocator, "GET", "/test");
    defer get_request.deinit();
    
    const route = TestRoute{
        .path = "/test",
    };
    
    var context = try middleware.types.Context.init(allocator, &get_request, &route);
    defer context.deinit();
    
    // First request should miss cache
    const result1 = try cache_middleware.process(&context);
    try testing.expect(result1.success);
    
    // Cache a response
    try cache_middleware.cacheResponse(&context, "Cached response");
    
    // Second request should hit cache
    const result2 = try cache_middleware.process(&context);
    try testing.expect(!result2.success);
    try testing.expectEqual(@as(u16, 200), result2.status_code);
    try testing.expectEqualStrings("Cached response", result2.error_message);
    
    // Test non-GET request
    var post_request = try TestRequest.init(allocator, "POST", "/test");
    defer post_request.deinit();
    
    var post_context = try middleware.types.Context.init(allocator, &post_request, &route);
    defer post_context.deinit();
    
    // POST request should bypass cache
    const result3 = try cache_middleware.process(&post_context);
    try testing.expect(result3.success);
}
