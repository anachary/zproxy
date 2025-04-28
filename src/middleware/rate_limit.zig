const std = @import("std");
const middleware = @import("middleware.zig");
const logger = @import("../utils/logger.zig");

/// Rate limiting middleware
pub const RateLimitMiddleware = struct {
    base: middleware.Middleware,
    allocator: std.mem.Allocator,
    
    // Rate limiting configuration
    requests_per_minute: u32,
    
    // Rate limiting state (simplified)
    last_reset: i64,
    request_count: std.AutoHashMap(u64, u32),
    
    /// Initialize rate limiting middleware
    pub fn init(allocator: std.mem.Allocator, middleware_config: std.json.Value) !*middleware.Middleware {
        var self = try allocator.create(RateLimitMiddleware);
        errdefer allocator.destroy(self);
        
        // Parse configuration
        const requests_per_minute = middleware_config.Object.get("requests_per_minute").?.Integer;
        
        self.* = RateLimitMiddleware{
            .base = middleware.Middleware{
                .applyFn = applyRateLimit,
                .initFn = undefined, // Not used directly
                .deinitFn = deinitRateLimit,
            },
            .allocator = allocator,
            .requests_per_minute = @intCast(requests_per_minute),
            .last_reset = std.time.timestamp(),
            .request_count = std.AutoHashMap(u64, u32).init(allocator),
        };
        
        return &self.base;
    }
    
    /// Apply rate limiting middleware
    fn applyRateLimit(middleware_ptr: *middleware.Middleware, request: anytype, route: anytype) !middleware.MiddlewareResult {
        _ = route;
        
        var self = @fieldParentPtr(RateLimitMiddleware, "base", middleware_ptr);
        
        // Get client IP as a hash
        const client_ip_hash = hashClientIp(request.client_addr);
        
        // Check if we need to reset counters
        const now = std.time.timestamp();
        if (now - self.last_reset >= 60) {
            self.request_count.clearRetainingCapacity();
            self.last_reset = now;
        }
        
        // Get current count for this client
        const count = self.request_count.get(client_ip_hash) orelse 0;
        
        // Check if rate limit is exceeded
        if (count >= self.requests_per_minute) {
            return middleware.MiddlewareResult{
                .allowed = false,
                .reason = try self.allocator.dupe(u8, "Rate limit exceeded"),
            };
        }
        
        // Increment count
        try self.request_count.put(client_ip_hash, count + 1);
        
        return middleware.MiddlewareResult{
            .allowed = true,
            .reason = try self.allocator.dupe(u8, ""),
        };
    }
    
    /// Clean up rate limiting middleware
    fn deinitRateLimit(middleware_ptr: *middleware.Middleware) void {
        var self = @fieldParentPtr(RateLimitMiddleware, "base", middleware_ptr);
        
        self.request_count.deinit();
        self.allocator.destroy(self);
    }
};

/// Hash a client IP address
fn hashClientIp(client_addr: std.net.Address) u64 {
    var hasher = std.hash.Wyhash.init(0);
    const ip_bytes = client_addr.any.toBytes();
    std.hash.autoHash(&hasher, ip_bytes);
    return hasher.final();
}
