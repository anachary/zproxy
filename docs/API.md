# ZProxy API Reference

This document describes the API for programmatically configuring and using ZProxy.

## Gateway Module

The main module provides access to all gateway functionality.

```zig
const gateway = @import("gateway");
```

### Gateway

The `Gateway` struct is the main entry point for the gateway.

```zig
// Initialize a new gateway
var gw = try gateway.Gateway.init(allocator, config);
defer gw.deinit();

// Run the gateway
try gw.run();

// Shutdown the gateway
gw.shutdown();
```

### Configuration

The `config` module provides types for configuring the gateway.

```zig
// Create a new configuration
var config = try gateway.config.Config.init(allocator);
defer config.deinit();

// Load configuration from a file
var config = try gateway.config.Config.loadFromFile(allocator, "config.json");
defer config.deinit();

// Configure listen address and port
config.listen_address = "0.0.0.0";
config.listen_port = 8080;

// Add a route
const route = try gateway.config.Route.init(
    allocator,
    "/api",
    "http://localhost:3000",
    &[_][]const u8{ "GET", "POST" },
    &[_][]const u8{ "auth", "ratelimit" }
);

config.routes = try allocator.alloc(gateway.config.Route, 1);
config.routes[0] = route;
```

### Router

The `router` module provides types for routing requests.

```zig
// Create a router
var router = try gateway.router.Router.init(allocator, routes);
defer router.deinit();

// Find a route for a request
const route = try router.findRoute("/api/users", "GET");
if (route != null) {
    // Route found
}

// Apply middleware
const result = try router.applyMiddleware(context);
if (result.success) {
    // Middleware allowed the request
} else {
    // Middleware rejected the request
    const status_code = result.status_code;
    const error_message = result.error_message;
}
```

### Middleware

The `middleware` module provides types for request processing middleware.

```zig
// Create a middleware chain
var chain = try gateway.middleware.chain.MiddlewareChain.init(allocator);
defer chain.deinit();

// Add middleware to the chain
try chain.add(rate_limit_middleware);
try chain.add(auth_middleware);
try chain.add(cache_middleware);

// Process a request through the middleware chain
const result = try chain.process(context);
if (result.success) {
    // Request allowed
} else {
    // Request rejected
}
```

#### Rate Limiting

```zig
// Create rate limit middleware
var rate_limit = try gateway.middleware.ratelimit.RateLimitMiddleware.create(
    allocator,
    .{ .requests_per_minute = 100 }
);
```

#### Authentication

```zig
// Create JWT authentication middleware
var jwt = try gateway.middleware.jwt.JwtMiddleware.create(
    allocator,
    .{ .jwt_secret = "your-secret-key" }
);
```

#### Caching

```zig
// Create cache middleware
var cache = try gateway.middleware.cache.CacheMiddleware.create(
    allocator,
    .{ .ttl_seconds = 300 }
);
```

### Protocol Handling

The `protocol` module provides types for handling different protocols.

```zig
// Detect protocol
const protocol = try gateway.protocol.detectProtocol(connection);

// Handle protocol
switch (protocol) {
    .http1 => try gateway.protocol.http1.handle(connection),
    .http2 => try gateway.protocol.http2.handle(connection),
    .websocket => try gateway.protocol.websocket.handle(connection),
    .unknown => {
        // Unknown protocol
    },
}
```

### TLS

The `tls` module provides types for TLS configuration and certificate management.

```zig
// Create TLS manager
var tls_manager = try gateway.tls.Manager.init(allocator, tls_config);
defer tls_manager.deinit();

// Get certificate for a domain
const cert = tls_manager.getCertificate("example.com");
if (cert != null) {
    // Certificate found
}
```

### Metrics

The `metrics` module provides types for collecting and reporting metrics.

```zig
// Create metrics collector
var collector = try gateway.metrics.Collector.init(allocator);
defer collector.deinit();

// Increment a counter
try collector.incrementCounter("requests_total", 1);

// Set a gauge
try collector.setGauge("connections_active", 10);

// Record a histogram value
try collector.recordHistogram("request_duration_ms", 42.5);

// Report metrics
try collector.report();
```

### Utilities

The `utils` module provides utility types and functions.

```zig
// Create an arena allocator
var arena = gateway.utils.ArenaAllocator.init(allocator);
defer arena.deinit();

// Create a buffer pool
var pool = gateway.utils.buffer.BufferPool.init(allocator, 8192, 100);
defer pool.deinit();

// Create a string builder
var builder = gateway.utils.buffer.StringBuilder.init(allocator);
defer builder.deinit();

// Get current time
const now = gateway.utils.time.currentTimeMillis();

// Format a timestamp
const formatted = try gateway.utils.time.formatTimestamp(allocator, now);
defer allocator.free(formatted);

// Create a timer
var timer = gateway.utils.time.Timer.start();
const elapsed = timer.elapsedMillis();
```

## Error Handling

The gateway uses Zig's error handling system. Most functions return an error union that should be handled with `try` or `catch`.

```zig
// Handle errors with try
try gw.run();

// Handle errors with catch
gw.run() catch |err| {
    std.debug.print("Error: {}\n", .{err});
    return;
};
```

## Memory Management

The gateway uses explicit memory management. Most functions that allocate memory take an allocator parameter and return resources that must be freed.

```zig
// Create a resource
var resource = try createResource(allocator);
defer resource.deinit();
```

## Thread Safety

The gateway is designed to be thread-safe. Concurrent access to shared resources is protected by mutexes.

```zig
// Thread-safe access to shared resources
self.mutex.lock();
defer self.mutex.unlock();

// Perform thread-safe operations
```

## Examples

See the `examples` directory for complete examples of using the gateway API.
