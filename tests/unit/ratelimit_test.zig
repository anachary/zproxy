const std = @import("std");
const testing = std.testing;
const middleware = @import("middleware");

test "Rate limiting middleware" {
    const allocator = testing.allocator;
    
    // Create rate limit middleware
    const TestConfig = struct {
        requests_per_minute: u32,
    };
    
    const config = TestConfig{
        .requests_per_minute = 2,
    };
    
    var rate_limit = try middleware.ratelimit.RateLimitMiddleware.create(allocator, config);
    defer allocator.destroy(@ptrCast(rate_limit));
    
    // Create mock context
    const TestRequest = struct {
        headers: std.StringHashMap([]const u8),
        
        pub fn init(allocator: std.mem.Allocator) !TestRequest {
            var headers = std.StringHashMap([]const u8).init(allocator);
            try headers.put("X-Forwarded-For", "127.0.0.1");
            
            return TestRequest{
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
    
    var request = try TestRequest.init(allocator);
    defer request.deinit();
    
    const route = TestRoute{
        .path = "/test",
    };
    
    var context = try middleware.types.Context.init(allocator, &request, &route);
    defer context.deinit();
    
    // First request should succeed
    const result1 = try rate_limit.process(&context);
    try testing.expect(result1.success);
    
    // Second request should succeed
    const result2 = try rate_limit.process(&context);
    try testing.expect(result2.success);
    
    // Third request should be rate limited
    const result3 = try rate_limit.process(&context);
    try testing.expect(!result3.success);
    try testing.expectEqual(@as(u16, 429), result3.status_code);
    try testing.expectEqualStrings("Rate limit exceeded", result3.error_message);
}
