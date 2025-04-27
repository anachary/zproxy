const std = @import("std");
const testing = std.testing;
const middleware = @import("middleware");

test "Middleware chain" {
    const allocator = testing.allocator;
    
    // Create middleware chain
    var chain = middleware.chain.MiddlewareChain.init(allocator);
    defer chain.deinit();
    
    // Create mock middleware
    const MockMiddleware = struct {
        allocator: std.mem.Allocator,
        should_succeed: bool,
        status_code: u16,
        error_message: []const u8,
        
        pub fn create(allocator: std.mem.Allocator, should_succeed: bool, status_code: u16, error_message: []const u8) !*middleware.types.Middleware {
            var mock = try allocator.create(@This());
            mock.* = .{
                .allocator = allocator,
                .should_succeed = should_succeed,
                .status_code = status_code,
                .error_message = error_message,
            };
            return @ptrCast(mock);
        }
        
        pub fn process(self: *const @This(), context: *middleware.types.Context) !middleware.types.Result {
            _ = context;
            if (self.should_succeed) {
                return middleware.types.Result{ .success = true };
            } else {
                return middleware.types.Result{
                    .success = false,
                    .status_code = self.status_code,
                    .error_message = self.error_message,
                };
            }
        }
    };
    
    // Create mock context
    const TestRequest = struct {
        method: []const u8,
        path: []const u8,
    };
    
    const TestRoute = struct {
        path: []const u8,
    };
    
    const request = TestRequest{
        .method = "GET",
        .path = "/test",
    };
    
    const route = TestRoute{
        .path = "/test",
    };
    
    var context = try middleware.types.Context.init(allocator, &request, &route);
    defer context.deinit();
    
    // Test empty chain
    const empty_result = try chain.process(&context);
    try testing.expect(empty_result.success);
    
    // Test successful middleware
    const success_middleware = try MockMiddleware.create(allocator, true, 200, "");
    try chain.add(success_middleware);
    
    const success_result = try chain.process(&context);
    try testing.expect(success_result.success);
    
    // Test failing middleware
    const fail_middleware = try MockMiddleware.create(allocator, false, 403, "Access denied");
    try chain.add(fail_middleware);
    
    const fail_result = try chain.process(&context);
    try testing.expect(!fail_result.success);
    try testing.expectEqual(@as(u16, 403), fail_result.status_code);
    try testing.expectEqualStrings("Access denied", fail_result.error_message);
}
