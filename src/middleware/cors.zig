const std = @import("std");
const middleware = @import("middleware.zig");
const logger = @import("../utils/logger.zig");

/// CORS middleware
pub const CorsMiddleware = struct {
    base: middleware.Middleware,
    allocator: std.mem.Allocator,
    
    // CORS configuration
    allowed_origins: std.StringHashMap(void),
    allow_credentials: bool,
    
    /// Initialize CORS middleware
    pub fn init(allocator: std.mem.Allocator, middleware_config: std.json.Value) !*middleware.Middleware {
        var self = try allocator.create(CorsMiddleware);
        errdefer allocator.destroy(self);
        
        // Parse configuration
        var allowed_origins = std.StringHashMap(void).init(allocator);
        
        const origins_array = middleware_config.Object.get("allowed_origins").?.Array;
        for (origins_array.items) |origin_value| {
            const origin = origin_value.String;
            try allowed_origins.put(origin, {});
        }
        
        const allow_credentials = middleware_config.Object.get("allow_credentials").?.Bool;
        
        self.* = CorsMiddleware{
            .base = middleware.Middleware{
                .applyFn = applyCors,
                .initFn = undefined, // Not used directly
                .deinitFn = deinitCors,
            },
            .allocator = allocator,
            .allowed_origins = allowed_origins,
            .allow_credentials = allow_credentials,
        };
        
        return &self.base;
    }
    
    /// Apply CORS middleware
    fn applyCors(middleware_ptr: *middleware.Middleware, request: anytype, route: anytype) !middleware.MiddlewareResult {
        _ = route;
        
        var self = @fieldParentPtr(CorsMiddleware, "base", middleware_ptr);
        
        // Get origin from request (simplified)
        const origin = getOrigin(request) orelse {
            // No origin header, not a CORS request
            return middleware.MiddlewareResult{
                .allowed = true,
                .reason = try self.allocator.dupe(u8, ""),
            };
        };
        
        // Check if origin is allowed
        if (!self.allowed_origins.contains(origin) and !self.allowed_origins.contains("*")) {
            return middleware.MiddlewareResult{
                .allowed = false,
                .reason = try self.allocator.dupe(u8, "Origin not allowed"),
            };
        }
        
        // Set CORS headers (in a real implementation, we would modify the response)
        
        return middleware.MiddlewareResult{
            .allowed = true,
            .reason = try self.allocator.dupe(u8, ""),
        };
    }
    
    /// Clean up CORS middleware
    fn deinitCors(middleware_ptr: *middleware.Middleware) void {
        var self = @fieldParentPtr(CorsMiddleware, "base", middleware_ptr);
        
        self.allowed_origins.deinit();
        self.allocator.destroy(self);
    }
};

/// Get origin from request (simplified)
fn getOrigin(request: anytype) ?[]const u8 {
    _ = request;
    // In a real implementation, we would extract the Origin header from the request
    return null;
}
