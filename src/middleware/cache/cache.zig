const std = @import("std");
const types = @import("../types.zig");
const store = @import("store.zig");

/// Cache middleware
pub const CacheMiddleware = struct {
    allocator: std.mem.Allocator,
    cache_store: store.CacheStore,
    ttl_seconds: u32,

    /// Create a new cache middleware
    pub fn create(allocator: std.mem.Allocator, config: anytype) !*types.Middleware {
        var middleware = try allocator.create(CacheMiddleware);

        var cache_store = try store.CacheStore.init(allocator);

        const ttl_seconds = if (@hasField(@TypeOf(config), "ttl_seconds"))
            config.ttl_seconds
        else
            300; // Default: 5 minutes

        middleware.* = CacheMiddleware{
            .allocator = allocator,
            .cache_store = cache_store,
            .ttl_seconds = ttl_seconds,
        };

        return @ptrCast(middleware);
    }

    /// Clean up resources
    pub fn deinit(self: *CacheMiddleware) void {
        self.cache_store.deinit();
    }

    /// Process a request
    pub fn process(self: *const CacheMiddleware, context: *types.Context) !types.Result {
        // Only cache GET requests
        if (!std.mem.eql(u8, context.request.method, "GET")) {
            return types.Result{ .success = true };
        }

        // Generate cache key
        const cache_key = try self.generateCacheKey(context);
        defer self.allocator.free(cache_key);

        // Check if response is in cache
        if (try self.cache_store.get(cache_key)) |cached_response| {
            // Add cached response to context
            try self.addCachedResponseToContext(context, cached_response);

            // Skip further processing
            return types.Result{
                .success = false,
                .status_code = 200,
                .error_message = "Cached response",
            };
        }

        // Response not in cache, continue processing
        return types.Result{ .success = true };
    }

    /// Generate a cache key for the request
    fn generateCacheKey(self: *const CacheMiddleware, context: *types.Context) ![]const u8 {
        // In a real implementation, this would generate a key based on:
        // - Request path
        // - Query parameters
        // - Relevant headers (e.g., Accept, Accept-Encoding)
        // - User information (for personalized responses)

        // For simplicity, we'll just use the path
        return self.allocator.dupe(u8, context.request.path);
    }

    /// Add cached response to context
    fn addCachedResponseToContext(self: *const CacheMiddleware, context: *types.Context, cached_response: []const u8) !void {
        // In a real implementation, this would:
        // 1. Parse the cached response
        // 2. Add it to the context for use by the handler
        // 3. Set a flag to indicate that the response is from cache
        _ = self;
        _ = context;
        _ = cached_response;
    }

    /// Cache a response
    pub fn cacheResponse(self: *const CacheMiddleware, context: *types.Context, response: []const u8) !void {
        // Only cache GET requests
        if (!std.mem.eql(u8, context.request.method, "GET")) {
            return;
        }

        // Generate cache key
        const cache_key = try self.generateCacheKey(context);
        defer self.allocator.free(cache_key);

        // Store response in cache
        try self.cache_store.set(cache_key, response, self.ttl_seconds);
    }
};
