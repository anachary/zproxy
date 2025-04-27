const std = @import("std");
const types = @import("types.zig");

/// Middleware factory function type
pub const MiddlewareFactory = *const fn (allocator: std.mem.Allocator, config: anytype) anyerror!*types.Middleware;

/// Middleware registry for storing and retrieving middleware factories
pub const Registry = struct {
    allocator: std.mem.Allocator,
    factories: std.StringHashMap(MiddlewareFactory),

    /// Initialize a new middleware registry
    pub fn init(allocator: std.mem.Allocator) Registry {
        return Registry{
            .allocator = allocator,
            .factories = std.StringHashMap(MiddlewareFactory).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Registry) void {
        self.factories.deinit();
    }

    /// Register a middleware factory
    pub fn register(self: *Registry, name: []const u8, comptime factory: MiddlewareFactory) !void {
        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);

        try self.factories.put(key, factory);
    }

    /// Get a middleware factory by name
    pub fn get(self: *Registry, name: []const u8) ?MiddlewareFactory {
        return self.factories.get(name);
    }

    /// Create a middleware instance by name
    pub fn create(self: *Registry, name: []const u8, config: anytype) !?*types.Middleware {
        if (self.get(name)) |factory| {
            return try factory(self.allocator, config);
        }
        return null;
    }
};

/// Global middleware registry
var global_registry: ?Registry = null;

/// Initialize the global middleware registry
pub fn initGlobalRegistry(allocator: std.mem.Allocator) !void {
    if (global_registry != null) {
        return error.AlreadyInitialized;
    }
    global_registry = Registry.init(allocator);
}

/// Clean up the global middleware registry
pub fn deinitGlobalRegistry() void {
    if (global_registry) |*registry| {
        registry.deinit();
        global_registry = null;
    }
}

/// Register a middleware factory in the global registry
pub fn register(name: []const u8, comptime factory: MiddlewareFactory) !void {
    if (global_registry) |*registry| {
        try registry.register(name, factory);
    } else {
        return error.RegistryNotInitialized;
    }
}

/// Get a middleware factory by name from the global registry
pub fn get(name: []const u8) ?MiddlewareFactory {
    if (global_registry) |*registry| {
        return registry.get(name);
    }
    return null;
}

/// Create a middleware instance by name from the global registry
pub fn create(name: []const u8, config: anytype) !?*types.Middleware {
    if (global_registry) |*registry| {
        return try registry.create(name, config);
    }
    return null;
}

test "middleware registry" {
    const testing = std.testing;

    // Initialize registry
    var registry = Registry.init(testing.allocator);
    defer registry.deinit();

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
                    .deinitFn = deinit,
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

        fn deinit(base: *types.Middleware) void {
            const self = @fieldParentPtr(@This(), "base", base);
            self.allocator.destroy(self);
        }
    };

    // Register the middleware factory
    try registry.register("test", TestMiddleware.create);

    // Get the middleware factory
    const factory = registry.get("test");
    try testing.expect(factory != null);

    // Create a middleware instance
    const middleware = try registry.create("test", .{});
    try testing.expect(middleware != null);
    defer middleware.?.deinit();

    // Test the middleware
    var context = try types.Context.init(testing.allocator, undefined, undefined);
    defer context.deinit();

    const result = try middleware.?.process(&context);
    try testing.expect(result.success);
    try testing.expectEqual(@as(u16, 200), result.status_code);
}
