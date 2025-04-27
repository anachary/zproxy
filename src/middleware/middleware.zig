const std = @import("std");

pub const types = @import("types.zig");
pub const registry = @import("registry.zig");

// Re-export modules
pub usingnamespace types;
pub usingnamespace registry;

/// Initialize the middleware system
pub fn init(allocator: std.mem.Allocator) !void {
    try registry.initGlobalRegistry(allocator);
}

/// Clean up the middleware system
pub fn deinit() void {
    registry.deinitGlobalRegistry();
}

/// Register a middleware factory
pub fn register(name: []const u8, factory: registry.MiddlewareFactory) !void {
    try registry.register(name, factory);
}

/// Create a middleware instance by name
pub fn create(name: []const u8, config: anytype) !?*types.Middleware {
    return try registry.create(name, config);
}

/// Apply middleware to a request
pub fn apply(middleware_list: []const []const u8, context: *types.Context) !types.MiddlewareResult {
    for (middleware_list) |middleware_name| {
        if (try create(middleware_name, .{})) |middleware| {
            defer middleware.deinit();

            const result = try middleware.process(context);
            if (!result.success) {
                return result;
            }
        }
    }

    return types.MiddlewareResult{
        .success = true,
        .status_code = 200,
        .error_message = "",
    };
}

test "middleware system" {
    const testing = std.testing;

    // Initialize middleware system
    try init(testing.allocator);
    defer deinit();

    // Define a test middleware factory
    const TestMiddleware = struct {
        base: types.Middleware,
        allocator: std.mem.Allocator,

        fn create(allocator: std.mem.Allocator, config: anytype) !*types.Middleware {
            _ = config;
            var self = try allocator.create(@This());
            self.* = .{
                .base = .{
                    .processFn = process,
                    .deinitFn = destroyMiddleware,
                },
                .allocator = allocator,
            };
            return &self.base;
        }

        fn process(base: *types.Middleware, context: *types.Context) !types.MiddlewareResult {
            _ = base;
            _ = context;
            return types.MiddlewareResult{
                .success = true,
                .status_code = 200,
                .error_message = "",
            };
        }

        fn destroyMiddleware(base: *types.Middleware) void {
            const self = @fieldParentPtr(@This(), "base", base);
            self.allocator.destroy(self);
        }
    };

    // Register the middleware factory
    try register("test", TestMiddleware.create);

    // Create a middleware instance
    const middleware = try create("test", .{});
    try testing.expect(middleware != null);
    defer middleware.?.deinit();

    // Test the middleware
    var context = try types.Context.init(testing.allocator, undefined, undefined);
    defer context.deinit();

    const result = try middleware.?.process(&context);
    try testing.expect(result.success);
    try testing.expectEqual(@as(u16, 200), result.status_code);
}
