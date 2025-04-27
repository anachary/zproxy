const std = @import("std");
const types = @import("types.zig");

/// A compile-time middleware chain
/// This is a Zig-idiomatic approach that uses comptime to define middleware chains
pub fn StaticChain(comptime MiddlewareTypes: anytype) type {
    // Generate a struct type with fields for each middleware
    const MiddlewareStruct = blk: {
        var fields: [MiddlewareTypes.len]std.builtin.Type.StructField = undefined;

        inline for (MiddlewareTypes, 0..) |M, i| {
            const field_name = comptime std.fmt.comptimePrint("m{d}", .{i});
            fields[i] = .{
                .name = field_name,
                .type = M,
                .default_value = null,
                .is_comptime = false,
                .alignment = @alignOf(M),
            };
        }

        break :blk @Type(.{
            .Struct = .{
                .layout = .Auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    };

    return struct {
        allocator: std.mem.Allocator,
        middlewares: MiddlewareStruct,

        const Self = @This();

        /// Initialize the middleware chain with specific configurations
        pub fn init(allocator: std.mem.Allocator, configs: anytype) !Self {
            // Validate configs at compile time
            comptime {
                if (configs.len != MiddlewareTypes.len) {
                    @compileError("Number of configurations must match number of middleware types");
                }
            }

            var middlewares: MiddlewareStruct = undefined;

            // Initialize each middleware with its configuration
            inline for (MiddlewareTypes, 0..) |M, i| {
                const field_name = comptime std.fmt.comptimePrint("m{d}", .{i});
                @field(middlewares, field_name) = try M.init(allocator, configs[i]);
            }

            return Self{
                .allocator = allocator,
                .middlewares = middlewares,
            };
        }

        /// Process a request through the middleware chain
        pub fn process(self: *Self, context: *types.Context) !types.MiddlewareResult {
            // Process through each middleware in order
            inline for (0..MiddlewareTypes.len) |i| {
                const field_name = comptime std.fmt.comptimePrint("m{d}", .{i});
                const result = try @field(self.middlewares, field_name).process(context);
                if (!result.success) {
                    return result;
                }
            }

            return types.MiddlewareResult{
                .success = true,
                .status_code = 200,
                .error_message = "",
            };
        }

        /// Clean up resources
        pub fn deinit(self: *Self) void {
            inline for (0..MiddlewareTypes.len) |i| {
                const field_name = comptime std.fmt.comptimePrint("m{d}", .{i});
                @field(self.middlewares, field_name).deinit();
            }
        }
    };
}

/// The original dynamic middleware chain (kept for backward compatibility)
pub const MiddlewareChain = struct {
    allocator: std.mem.Allocator,
    middlewares: std.ArrayList(*types.Middleware),

    /// Initialize a new middleware chain
    pub fn init(allocator: std.mem.Allocator) MiddlewareChain {
        return MiddlewareChain{
            .allocator = allocator,
            .middlewares = std.ArrayList(*types.Middleware).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *MiddlewareChain) void {
        for (self.middlewares.items) |middleware| {
            middleware.deinit();
            self.allocator.destroy(middleware);
        }
        self.middlewares.deinit();
    }

    /// Add a middleware to the chain
    pub fn add(self: *MiddlewareChain, middleware: *types.Middleware) !void {
        try self.middlewares.append(middleware);
    }

    /// Process a request through the middleware chain
    pub fn process(self: *const MiddlewareChain, context: *types.Context) !types.MiddlewareResult {
        for (self.middlewares.items) |middleware| {
            const result = try middleware.process(context);
            if (!result.success) {
                return result;
            }
        }

        return types.MiddlewareResult{
            .success = true,
            .status_code = 200,
            .error_message = "",
        };
    }
};

/// Create a middleware chain from a list of middleware names
/// This is kept for backward compatibility
pub fn createChain(
    allocator: std.mem.Allocator,
    middleware_names: []const []const u8,
    registry: *const @import("registry.zig").Registry,
    config: anytype,
) !MiddlewareChain {
    var chain = MiddlewareChain.init(allocator);
    errdefer chain.deinit();

    for (middleware_names) |name| {
        if (try registry.create(name, config)) |middleware| {
            try chain.add(middleware);
        } else {
            return error.MiddlewareNotFound;
        }
    }

    return chain;
}

test "static chain with dummy middleware" {
    const testing = std.testing;

    // Define a simple test middleware
    const DummyMiddleware = struct {
        value: u32,

        pub fn init(allocator: std.mem.Allocator, config: struct { value: u32 }) !@This() {
            _ = allocator;
            return .{ .value = config.value };
        }

        pub fn process(self: *const @This(), context: *types.Context) !types.MiddlewareResult {
            _ = context;
            _ = self;
            return types.MiddlewareResult{
                .success = true,
                .status_code = 200,
                .error_message = "",
            };
        }

        pub fn deinit(self: *const @This()) void {
            _ = self;
            // Nothing to clean up
        }
    };

    // Define a middleware chain with our test middleware
    const MyChain = StaticChain(.{DummyMiddleware});

    // Create configuration
    const configs = .{.{ .value = 42 }};

    // Initialize the chain
    var chain = try MyChain.init(testing.allocator, configs);
    defer chain.deinit();

    // Create a dummy context
    var request = types.Request{
        .method = "GET",
        .path = "/test",
        .headers = std.StringHashMap([]const u8).init(testing.allocator),
    };

    var route = types.Route{
        .path = "/test",
        .upstream = "http://example.com",
    };

    var context = types.Context{
        .allocator = testing.allocator,
        .request = &request,
        .route = &route,
    };

    // Process the request
    const result = try chain.process(&context);

    // Verify the result
    try testing.expect(result.success);
    try testing.expectEqual(@as(u16, 200), result.status_code);
}
