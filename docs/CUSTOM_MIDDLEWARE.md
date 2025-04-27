# Creating Custom Middleware for ZProxy

This guide explains how to create and use custom middleware with ZProxy.

## Middleware Interface

ZProxy middleware follows a simple interface pattern. To create custom middleware, you need to implement this interface:

```zig
// src/middleware/types.zig
pub const Middleware = struct {
    // Function pointer to the process method
    processFn: *const fn (self: *Middleware, context: *Context) anyerror!MiddlewareResult,
    
    // Process a request through this middleware
    pub fn process(self: *Middleware, context: *Context) anyerror!MiddlewareResult {
        return self.processFn(self, context);
    }
    
    // Function pointer to the deinit method
    deinitFn: *const fn (self: *Middleware) void,
    
    // Clean up resources
    pub fn deinit(self: *Middleware) void {
        self.deinitFn(self);
    }
};
```

## Creating Custom Middleware

Here's how to create a custom middleware:

```zig
const std = @import("std");
const middleware = @import("middleware");

// Define your middleware struct
pub const LoggingMiddleware = struct {
    // Base middleware interface
    base: middleware.types.Middleware,
    
    // Middleware-specific fields
    allocator: std.mem.Allocator,
    log_level: LogLevel,
    
    // Log levels
    pub const LogLevel = enum {
        debug,
        info,
        warn,
        error,
    };
    
    // Create a new logging middleware
    pub fn create(allocator: std.mem.Allocator, config: anytype) !*middleware.types.Middleware {
        // Allocate memory for the middleware
        var self = try allocator.create(LoggingMiddleware);
        
        // Initialize the middleware
        self.* = LoggingMiddleware{
            .base = middleware.types.Middleware{
                .processFn = process,
                .deinitFn = deinit,
            },
            .allocator = allocator,
            .log_level = config.log_level,
        };
        
        return &self.base;
    }
    
    // Process a request through this middleware
    fn process(base: *middleware.types.Middleware, context: *middleware.types.Context) !middleware.types.MiddlewareResult {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(LoggingMiddleware, "base", base);
        
        // Log the request
        const logger = std.log.scoped(.logging_middleware);
        switch (self.log_level) {
            .debug => logger.debug("Request: {s} {s}", .{ context.request.method, context.request.path }),
            .info => logger.info("Request: {s} {s}", .{ context.request.method, context.request.path }),
            .warn => logger.warn("Request: {s} {s}", .{ context.request.method, context.request.path }),
            .error => logger.err("Request: {s} {s}", .{ context.request.method, context.request.path }),
        }
        
        // Allow the request to continue
        return middleware.types.MiddlewareResult{
            .success = true,
            .status_code = 200,
            .error_message = "",
        };
    }
    
    // Clean up resources
    fn deinit(base: *middleware.types.Middleware) void {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(LoggingMiddleware, "base", base);
        
        // Free memory
        self.allocator.destroy(self);
    }
};
```

## Registering Custom Middleware

To use your custom middleware, you need to register it with ZProxy:

```zig
// Register middleware factory
try gateway.middleware.registry.register("logging", LoggingMiddleware.create);

// Use in configuration
var route = try gateway.config.Route.init(
    allocator,
    "/api/users",
    "http://users-service:8080",
    &[_][]const u8{ "GET", "POST" },
    &[_][]const u8{ "logging", "jwt" }, // Use "logging" middleware
);
```

## Middleware Configuration

You can configure your middleware using a JSON configuration:

```json
{
  "middleware": {
    "logging": {
      "enabled": true,
      "log_level": "info"
    }
  }
}
```

## Middleware Execution Order

Middleware is executed in the order it appears in the route's middleware list. For example:

```zig
&[_][]const u8{ "logging", "jwt", "ratelimit" }
```

In this example:
1. The `logging` middleware runs first
2. Then the `jwt` middleware
3. Finally, the `ratelimit` middleware

## Middleware Chain

ZProxy uses a middleware chain to process requests. Each middleware in the chain can:

1. **Allow the request** to continue to the next middleware
2. **Reject the request** with a status code and error message
3. **Modify the request** before passing it to the next middleware
4. **Modify the response** after the next middleware has processed it

## Example: Request Transformation Middleware

Here's an example of middleware that transforms requests:

```zig
pub const HeaderTransformMiddleware = struct {
    // Base middleware interface
    base: middleware.types.Middleware,
    
    // Middleware-specific fields
    allocator: std.mem.Allocator,
    add_headers: std.StringHashMap([]const u8),
    
    // Create a new header transform middleware
    pub fn create(allocator: std.mem.Allocator, config: anytype) !*middleware.types.Middleware {
        // Allocate memory for the middleware
        var self = try allocator.create(HeaderTransformMiddleware);
        
        // Initialize the middleware
        self.* = HeaderTransformMiddleware{
            .base = middleware.types.Middleware{
                .processFn = process,
                .deinitFn = deinit,
            },
            .allocator = allocator,
            .add_headers = std.StringHashMap([]const u8).init(allocator),
        };
        
        // Add headers from config
        if (@hasField(@TypeOf(config), "add_headers")) {
            for (config.add_headers) |header| {
                const key = try allocator.dupe(u8, header.key);
                const value = try allocator.dupe(u8, header.value);
                try self.add_headers.put(key, value);
            }
        }
        
        return &self.base;
    }
    
    // Process a request through this middleware
    fn process(base: *middleware.types.Middleware, context: *middleware.types.Context) !middleware.types.MiddlewareResult {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(HeaderTransformMiddleware, "base", base);
        
        // Add headers to the request
        var it = self.add_headers.iterator();
        while (it.next()) |entry| {
            try context.request.headers.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        
        // Allow the request to continue
        return middleware.types.MiddlewareResult{
            .success = true,
            .status_code = 200,
            .error_message = "",
        };
    }
    
    // Clean up resources
    fn deinit(base: *middleware.types.Middleware) void {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(HeaderTransformMiddleware, "base", base);
        
        // Free memory
        var it = self.add_headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.add_headers.deinit();
        self.allocator.destroy(self);
    }
};
```

## Advanced: Middleware with Next Function

For more advanced middleware patterns similar to .NET, we can implement a "next" function pattern:

```zig
pub const NextMiddleware = struct {
    // Base middleware interface
    base: middleware.types.Middleware,
    
    // Middleware-specific fields
    allocator: std.mem.Allocator,
    next: ?*middleware.types.Middleware,
    
    // Create a new middleware
    pub fn create(allocator: std.mem.Allocator, config: anytype) !*middleware.types.Middleware {
        // Allocate memory for the middleware
        var self = try allocator.create(NextMiddleware);
        
        // Initialize the middleware
        self.* = NextMiddleware{
            .base = middleware.types.Middleware{
                .processFn = process,
                .deinitFn = deinit,
            },
            .allocator = allocator,
            .next = null,
        };
        
        return &self.base;
    }
    
    // Set the next middleware in the chain
    pub fn setNext(self: *NextMiddleware, next: *middleware.types.Middleware) void {
        self.next = next;
    }
    
    // Process a request through this middleware
    fn process(base: *middleware.types.Middleware, context: *middleware.types.Context) !middleware.types.MiddlewareResult {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(NextMiddleware, "base", base);
        
        // Do something before the next middleware
        std.log.info("Before next middleware", .{});
        
        // Call the next middleware if it exists
        var result = middleware.types.MiddlewareResult{
            .success = true,
            .status_code = 200,
            .error_message = "",
        };
        
        if (self.next) |next| {
            result = try next.process(context);
        }
        
        // Do something after the next middleware
        std.log.info("After next middleware", .{});
        
        return result;
    }
    
    // Clean up resources
    fn deinit(base: *middleware.types.Middleware) void {
        // Cast to our specific middleware type
        const self = @fieldParentPtr(NextMiddleware, "base", base);
        
        // Free memory
        self.allocator.destroy(self);
    }
};
```

## Conclusion

By implementing these patterns, ZProxy can support custom middleware similar to .NET's middleware pipeline. This allows for flexible request/response processing and enables third-party extensions to the gateway.
