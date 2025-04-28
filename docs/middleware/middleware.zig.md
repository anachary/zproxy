# middleware.zig Documentation

## Overview

The `middleware.zig` file implements a flexible middleware system for ZProxy. Middleware components process requests before they are forwarded to upstream services, allowing for functionality like authentication, rate limiting, CORS, and caching.

## Key Components

### Middleware Result

```zig
pub const MiddlewareResult = struct {
    allowed: bool,
    reason: []const u8,
    
    pub fn deinit(self: *MiddlewareResult, allocator: std.mem.Allocator) void {
        allocator.free(self.reason);
    }
};
```

This structure represents the result of applying middleware:
- `allowed`: Whether the request is allowed to proceed
- `reason`: A message explaining why the request was blocked (if `allowed` is false)

The `deinit` method ensures proper cleanup of allocated memory.

### Middleware Interface

```zig
pub const Middleware = struct {
    applyFn: *const fn (middleware: *Middleware, request: anytype, route: anytype) anyerror!MiddlewareResult,
    initFn: *const fn (allocator: std.mem.Allocator, middleware_config: std.json.Value) anyerror!*Middleware,
    deinitFn: *const fn (middleware: *Middleware) void,
    
    pub fn apply(self: *Middleware, request: anytype, route: anytype) !MiddlewareResult {
        return self.applyFn(self, request, route);
    }
    
    pub fn init(allocator: std.mem.Allocator, middleware_config: std.json.Value) !*Middleware {
        return self.initFn(allocator, middleware_config);
    }
    
    pub fn deinit(self: *Middleware) void {
        self.deinitFn(self);
    }
};
```

This is the interface that all middleware components implement:
- `applyFn`: Function pointer for applying the middleware to a request
- `initFn`: Function pointer for initializing the middleware
- `deinitFn`: Function pointer for cleaning up the middleware

The interface methods provide a convenient way to call these functions.

### Middleware Chain

```zig
pub const MiddlewareChain = struct {
    allocator: std.mem.Allocator,
    middlewares: std.ArrayList(*Middleware),
    
    pub fn init(allocator: std.mem.Allocator) !MiddlewareChain {
        // Initialize the middleware chain
    }
    
    pub fn initFromConfig(allocator: std.mem.Allocator, middleware_config: []const config.MiddlewareConfig) !MiddlewareChain {
        // Initialize the middleware chain from configuration
    }
    
    pub fn add(self: *MiddlewareChain, middleware: *Middleware) !void {
        // Add a middleware to the chain
    }
    
    pub fn apply(self: *MiddlewareChain, request: anytype, route: anytype) !MiddlewareResult {
        // Apply all middlewares in the chain
    }
    
    pub fn deinit(self: *MiddlewareChain) void {
        // Clean up middleware chain resources
    }
};
```

This structure manages a chain of middleware components:
- `allocator`: Memory allocator
- `middlewares`: List of middleware components

Key methods:
- `init`: Initializes an empty middleware chain
- `initFromConfig`: Initializes a middleware chain from configuration
- `add`: Adds a middleware component to the chain
- `apply`: Applies all middleware components in the chain to a request
- `deinit`: Cleans up middleware chain resources

The `apply` method applies each middleware in sequence and stops if any middleware blocks the request.

### Middleware Implementations

The file includes several middleware implementations:

#### Rate Limiting Middleware

```zig
pub const RateLimitMiddleware = struct {
    base: Middleware,
    allocator: std.mem.Allocator,
    
    // Rate limiting configuration
    requests_per_minute: u32,
    
    // Rate limiting state
    last_reset: i64,
    request_count: std.AutoHashMap(u64, u32),
    
    // ... methods ...
};
```

This middleware limits the number of requests a client can make per minute:
- `requests_per_minute`: Maximum number of requests allowed per minute
- `last_reset`: Timestamp of the last counter reset
- `request_count`: Map of client IP hashes to request counts

#### Authentication Middleware

```zig
pub const AuthMiddleware = struct {
    base: Middleware,
    allocator: std.mem.Allocator,
    
    // Authentication configuration
    api_keys: std.StringHashMap(void),
    
    // ... methods ...
};
```

This middleware authenticates requests using API keys:
- `api_keys`: Set of valid API keys

#### CORS Middleware

```zig
pub const CorsMiddleware = struct {
    base: Middleware,
    allocator: std.mem.Allocator,
    
    // CORS configuration
    allowed_origins: std.StringHashMap(void),
    allow_credentials: bool,
    
    // ... methods ...
};
```

This middleware handles Cross-Origin Resource Sharing (CORS):
- `allowed_origins`: Set of allowed origins
- `allow_credentials`: Whether to allow credentials in CORS requests

#### Cache Middleware

```zig
pub const CacheMiddleware = struct {
    base: Middleware,
    allocator: std.mem.Allocator,
    
    // Cache configuration
    ttl_seconds: u32,
    
    // Cache state
    cache: std.StringHashMap(CacheEntry),
    
    // ... methods ...
};
```

This middleware caches responses to improve performance:
- `ttl_seconds`: Time-to-live for cached responses
- `cache`: Map of request paths to cached responses

### Helper Functions

```zig
fn hashClientIp(client_addr: std.net.Address) u64 {
    // Hash a client IP address
}

fn getApiKey(request: anytype) ?[]const u8 {
    // Get API key from request
}

fn getOrigin(request: anytype) ?[]const u8 {
    // Get origin from request
}
```

These helper functions are used by the middleware implementations:
- `hashClientIp`: Hashes a client IP address for use as a map key
- `getApiKey`: Extracts an API key from a request
- `getOrigin`: Extracts the Origin header from a request

### Testing

```zig
test "Middleware - Rate Limit" {
    // Test rate limiting middleware
}
```

This test ensures that the rate limiting middleware correctly limits requests.

## Zig Programming Principles

1. **Interface Implementation**: The middleware system uses a common interface with function pointers to implement polymorphism.
2. **Memory Management**: Each middleware component carefully manages memory, allocating space for data structures and providing `deinit` methods to free that memory.
3. **Error Handling**: Functions that can fail return errors using Zig's error union type.
4. **Generic Programming**: The `anytype` keyword is used for request and route parameters to allow different types to be passed.
5. **Testing**: Tests are integrated directly into the code.

## Usage Example

```zig
// Create middleware configuration
var middleware_configs = [_]config.MiddlewareConfig{
    .{
        .type = "rate_limit",
        .config = .{
            .Object = .{
                .get = .{
                    "requests_per_minute" = .{ .Integer = 100 },
                },
            },
        },
    },
    .{
        .type = "auth",
        .config = .{
            .Object = .{
                .get = .{
                    "api_keys" = .{
                        .Array = .{
                            .items = &[_]std.json.Value{
                                .{ .String = "api-key-1" },
                                .{ .String = "api-key-2" },
                            },
                        },
                    },
                },
            },
        },
    },
};

// Create middleware chain
var middleware_chain = try middleware.MiddlewareChain.initFromConfig(allocator, &middleware_configs);
defer middleware_chain.deinit();

// Apply middleware to a request
const result = try middleware_chain.apply(request, route);
defer result.deinit(allocator);

if (result.allowed) {
    // Request is allowed, proceed with handling
} else {
    // Request is blocked, return an error response
    logger.warning("Request blocked: {s}", .{result.reason});
}
```
