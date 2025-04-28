# router.zig Documentation

## Overview

The `router.zig` file implements the routing system for ZProxy. It matches incoming request paths to configured routes and extracts path parameters.

## Key Components

### Route Parameter Structure

```zig
pub const RouteParam = struct {
    name: []const u8,
    value: []const u8,
};
```

This structure represents a route parameter:
- `name`: The parameter name (e.g., "id" in "/users/:id")
- `value`: The parameter value from the request path

### Route Match Structure

```zig
pub const RouteMatch = struct {
    route: *const config.Route,
    params: []RouteParam,
    
    pub fn deinit(self: *RouteMatch, allocator: std.mem.Allocator) void {
        // Free allocated memory
    }
};
```

This structure represents a successful route match:
- `route`: A pointer to the matched route
- `params`: An array of extracted route parameters

The `deinit` method ensures proper cleanup of allocated memory.

### Router Structure

```zig
pub const Router = struct {
    allocator: std.mem.Allocator,
    routes: []config.Route,
    
    pub fn init(allocator: std.mem.Allocator, routes: []config.Route) !Router {
        // Initialize the router
    }
    
    pub fn deinit(self: *Router) void {
        // Clean up router resources
    }
    
    pub fn findRoute(self: *Router, path: []const u8, method: []const u8) ?*const config.Route {
        // Find a route that matches the given path and method
    }
    
    pub fn findRouteWithParams(self: *Router, path: []const u8, method: []const u8) !?RouteMatch {
        // Find a route with parameter extraction
    }
    
    fn matchPath(self: *Router, route_path: []const u8, request_path: []const u8) bool {
        // Check if a route path matches a request path
    }
    
    fn matchPathWithParams(self: *Router, route_path: []const u8, request_path: []const u8) !?[]RouteParam {
        // Match a path and extract parameters
    }
};
```

This is the main router structure:
- `allocator`: Memory allocator
- `routes`: Array of routes from the configuration

Key methods:
- `init`: Initializes the router with the given routes
- `deinit`: Cleans up router resources
- `findRoute`: Finds a route that matches a path and method
- `findRouteWithParams`: Finds a route and extracts path parameters
- `matchPath`: Checks if a route path matches a request path
- `matchPathWithParams`: Matches a path and extracts parameters

### Route Matching

The router supports three types of route matching:

1. **Exact Matching**: The route path exactly matches the request path
   ```
   Route: /api/users
   Request: /api/users
   ```

2. **Wildcard Matching**: The route path ends with "/*" and matches any path with the same prefix
   ```
   Route: /api/*
   Request: /api/users
   Request: /api/products/123
   ```

3. **Parameter Matching**: The route path contains parameters prefixed with ":" that match any value in that segment
   ```
   Route: /api/users/:id
   Request: /api/users/123
   ```

### Parameter Extraction

The `findRouteWithParams` method not only finds a matching route but also extracts path parameters:

```zig
// Example
Route: /api/users/:id/posts/:post_id
Request: /api/users/123/posts/456

// Extracted parameters
params[0].name = "id"
params[0].value = "123"
params[1].name = "post_id"
params[1].value = "456"
```

### Testing

```zig
test "Router - Exact Match" {
    // Test exact path matching
}

test "Router - Wildcard Match" {
    // Test wildcard path matching
}

test "Router - Parameter Match" {
    // Test parameter path matching and extraction
}
```

These tests ensure that the router correctly matches paths and extracts parameters for different types of routes.

## Zig Programming Principles

1. **Memory Management**: The router carefully manages memory for extracted parameters, allocating space for strings and providing `deinit` methods to free that memory.
2. **Error Handling**: Functions that can fail return errors using Zig's error union type.
3. **Optional Return Values**: The `?` syntax is used for functions that might not find a match.
4. **Testing**: Tests are integrated directly into the code, with each test case checking a specific type of route matching.
5. **Resource Safety**: The code uses `defer` statements to ensure resources are properly cleaned up, even if an error occurs.

## Usage Example

```zig
// Create a router
var router = try router.Router.init(allocator, config.routes);
defer router.deinit();

// Find a route
const route = router.findRoute("/api/users/123", "GET");
if (route) |r| {
    // Route found
    logger.info("Found route: {s} -> {s}", .{ r.path, r.upstream });
} else {
    // No route found
    logger.warning("No route found for /api/users/123", .{});
}

// Find a route with parameters
const match = try router.findRouteWithParams("/api/users/123", "GET");
if (match) |m| {
    defer m.deinit(allocator);
    
    // Route found with parameters
    logger.info("Found route: {s} -> {s}", .{ m.route.path, m.route.upstream });
    
    // Access parameters
    for (m.params) |param| {
        logger.info("Parameter {s} = {s}", .{ param.name, param.value });
    }
} else {
    // No route found
    logger.warning("No route found for /api/users/123", .{});
}
```
