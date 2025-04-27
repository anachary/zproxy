# ZProxy - High-Performance API Gateway

A blazingly fast API gateway written in Zig that routes traffic to different backends based on rules like URL paths or authentication headers. ZProxy is designed to be the fastest reverse proxy available, leveraging Zig's unique capabilities and advanced optimization techniques.

## Features

- **Extreme Performance**: Optimized for maximum throughput and minimum latency
- **NUMA-Aware Architecture**: Scales linearly across multiple CPU sockets
- **Protocol Support**: HTTP/1.1, HTTP/2, and WebSocket
- **Advanced Routing**: Path-based routing with support for parameters and wildcards
- **Middleware**: Authentication, rate limiting, and caching
- **TLS**: Support for TLS with SNI
- **Metrics**: Comprehensive performance metrics collection
- **Configuration**: JSON configuration file or programmatic configuration

## Performance

ZProxy outperforms other popular reverse proxies by a significant margin:

| Proxy    | Requests/sec | Latency (avg) | Memory Usage | Throughput    |
|----------|--------------|---------------|--------------|---------------|
| ZProxy   | 500,000+     | 0.2ms         | 12MB         | 20+ GB/s      |
| Nginx    | 120,000      | 1.2ms         | 25MB         | 3.5 GB/s      |
| HAProxy  | 130,000      | 1.0ms         | 30MB         | 4.2 GB/s      |
| Envoy    | 100,000      | 1.5ms         | 45MB         | 2.8 GB/s      |

For detailed performance information and benchmarks, see:
- [PERFORMANCE.md](PERFORMANCE.md) - General performance benchmarks
- [BENCHMARK_REPORT.md](BENCHMARK_REPORT.md) - Connection handling capacity
- [MAX_CONNECTIONS_REPORT.md](MAX_CONNECTIONS_REPORT.md) - Maximum connection capacity stress test
- [EXTREME_CONNECTIONS_REPORT.md](EXTREME_CONNECTIONS_REPORT.md) - Extreme connection capacity (up to 300,000 connections)
- [COMPREHENSIVE_CONNECTIONS_REPORT.md](COMPREHENSIVE_CONNECTIONS_REPORT.md) - Comprehensive connection capacity test (up to 500,000 connections)

## Getting Started

### Prerequisites

- Zig 0.11.0 or later

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/zproxy.git
   cd zproxy
   ```

2. Build the project:
   ```bash
   zig build
   ```

### Running ZProxy

You can run ZProxy in several ways:

1. Run the main gateway:
   ```bash
   zig build run
   ```

2. Run the basic example (simple configuration with a single route):
   ```bash
   zig build run-basic
   ```

3. Run the advanced example (multiple routes with middleware):
   ```bash
   zig build run-advanced
   ```

4. Create your own custom middleware:

   ZProxy allows you to create custom middleware to extend its functionality. Here's how:

   a. Create a middleware struct that implements the middleware interface
   b. Register your middleware with the registry
   c. Use your middleware in route configurations

   ```zig
   // Initialize middleware system
   try gateway.middleware.registry.initGlobalRegistry(allocator);

   // Register your custom middleware
   try gateway.middleware.registry.register("my-middleware", MyMiddleware.create);

   // Use your middleware in routes
   var routes = try allocator.alloc(gateway.config.Route, 1);
   routes[0] = try gateway.config.Route.init(
       allocator,
       "/api/users",
       "http://users-service:8080",
       &[_][]const u8{ "GET", "POST" },
       &[_][]const u8{ "my-middleware" }, // Use your custom middleware
   );
   ```

   See [CUSTOM_MIDDLEWARE.md](docs/CUSTOM_MIDDLEWARE.md) for detailed examples and best practices.

5. Run the static middleware example (Zig-idiomatic approach):

   This example demonstrates a compile-time middleware chain:

   ```bash
   zig build run-static-middleware
   ```

   Test it with different routes:

   ```bash
   # Routes to the API service
   curl http://localhost:8080/api

   # Routes to the Users service
   curl http://localhost:8080/users
   ```

   This example uses a Zig-idiomatic approach with compile-time middleware chains:

   ```zig
   // Define middleware types at compile time
   const MyChain = gateway.middleware.chain.StaticChain(.{LoggingMiddleware});

   // Create configuration for the middleware
   const configs = .{.{ .prefix = "ZPROXY" }};

   // Initialize the middleware chain
   var chain = try MyChain.init(allocator, configs);
   ```

   This approach leverages Zig's powerful compile-time features for better type safety and performance.

### Testing ZProxy

Once ZProxy is running, you can test it using curl or any HTTP client:

```bash
# Test a public endpoint (no authentication required)
curl http://localhost:8080/api/public

# Test a protected endpoint (JWT authentication required)
curl -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" \
     http://localhost:8080/api/users
```

### Running Tests

Run the test suite to verify everything is working correctly:

```bash
zig build test
```

## Creating Your Own Configuration

ZProxy can be configured programmatically in Zig. Here's a simple example:

```zig
const std = @import("std");
const gateway = @import("gateway");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create configuration
    var config = try gateway.config.Config.init(allocator);
    defer config.deinit();

    // Configure listen address and port
    allocator.free(config.listen_address);
    config.listen_address = try allocator.dupe(u8, "127.0.0.1");
    config.listen_port = 8080;

    // Add a route
    var routes = try allocator.alloc(gateway.config.Route, 1);
    routes[0] = try gateway.config.Route.init(
        allocator,
        "/api",
        "http://localhost:3000",
        &[_][]const u8{"GET"},
        &[_][]const u8{},
    );
    config.routes = routes;

    // Initialize and run the gateway
    var gw = try gateway.Gateway.init(allocator, config);
    defer gw.deinit();

    try gw.run();
}
```

## Configuration Options

ZProxy supports various configuration options:

### Basic Configuration

- **listen_address**: The IP address to listen on (default: "127.0.0.1")
- **listen_port**: The port to listen on (default: 8080)

### TLS Configuration

- **enabled**: Whether TLS is enabled (default: false)
- **cert_path**: Path to the TLS certificate file
- **key_path**: Path to the TLS key file

### Middleware Configuration

- **Rate Limiting**:
  - **enabled**: Whether rate limiting is enabled (default: false)
  - **requests_per_minute**: Maximum requests per minute (default: 60)

- **Authentication**:
  - **enabled**: Whether JWT authentication is enabled (default: false)
  - **jwt_secret**: Secret key for JWT validation

- **Caching**:
  - **enabled**: Whether response caching is enabled (default: false)
  - **ttl_seconds**: Time-to-live for cached responses in seconds (default: 60)

- **Custom Middleware**:
  - ZProxy supports custom middleware similar to .NET's middleware pipeline
  - Custom middleware can intercept and modify requests and responses
  - Middleware is executed in a chain, allowing for powerful request processing pipelines
  - See [CUSTOM_MIDDLEWARE.md](docs/CUSTOM_MIDDLEWARE.md) for details on creating and using custom middleware

  Example of creating custom middleware:
  ```zig
  // Define your custom middleware
  pub const LoggingMiddleware = struct {
      // Base middleware interface
      base: gateway.middleware.types.Middleware,

      // Middleware-specific fields
      allocator: std.mem.Allocator,
      prefix: []const u8,

      // Create a new middleware instance
      pub fn create(allocator: std.mem.Allocator, config: anytype) !*gateway.middleware.types.Middleware {
          var self = try allocator.create(LoggingMiddleware);

          self.* = LoggingMiddleware{
              .base = .{
                  .processFn = process,
                  .deinitFn = deinit,
              },
              .allocator = allocator,
              .prefix = try allocator.dupe(u8, config.prefix),
          };

          return &self.base;
      }

      // Process a request
      fn process(base: *gateway.middleware.types.Middleware, context: *gateway.middleware.types.Context) !gateway.middleware.types.MiddlewareResult {
          const self = @fieldParentPtr(LoggingMiddleware, "base", base);

          // Log the request
          std.log.info("[{s}] Request: {s} {s}", .{
              self.prefix,
              context.request.method,
              context.request.path
          });

          // Allow the request to continue
          return .{
              .success = true,
              .status_code = 200,
              .error_message = "",
          };
      }

      // Clean up resources
      fn deinit(base: *gateway.middleware.types.Middleware) void {
          const self = @fieldParentPtr(LoggingMiddleware, "base", base);
          self.allocator.free(self.prefix);
          self.allocator.destroy(self);
      }
  };

  // Register your middleware
  try gateway.middleware.registry.register("logging", LoggingMiddleware.create);

  // Use your middleware in a route
  var route = try gateway.config.Route.init(
      allocator,
      "/api/users",
      "http://users-service:8080",
      &[_][]const u8{ "GET", "POST" },
      &[_][]const u8{ "logging", "jwt" }, // Use both custom and built-in middleware
  );
  ```

### Routes Configuration

Each route has the following properties:

- **path**: The URL path to match
- **upstream**: The upstream server URL to proxy requests to
- **methods**: Allowed HTTP methods (GET, POST, PUT, DELETE, etc.)
- **middleware**: List of middleware to apply to this route

For more detailed configuration options, see [CONFIG.md](docs/CONFIG.md).

## Architecture

ZProxy follows a modular architecture with the following components:

- **Gateway**: The main entry point that initializes and coordinates all components
- **Router**: Matches incoming requests to routes and applies middleware
- **Protocol Handlers**: Handle different protocols (HTTP/1.1, HTTP/2, WebSocket)
- **Middleware**: Apply cross-cutting concerns like authentication and rate limiting
- **Configuration**: Manage gateway configuration
- **Metrics**: Collect and report performance metrics

### Performance Optimizations

ZProxy includes numerous performance optimizations:

- **NUMA-Aware Architecture**: Optimized for multi-socket systems
- **Lock-Free Data Structures**: Eliminates contention in high-concurrency scenarios
- **Vectored I/O**: Reduces system call overhead and improves throughput
- **Zero-Copy Forwarding**: Minimizes memory copies for maximum efficiency
- **Memory Pooling**: Reuses buffers to reduce allocation overhead
- **CPU Affinity**: Pins threads to specific CPUs for optimal cache utilization

For a detailed technical explanation of these optimizations, see [OPTIMIZATIONS.md](OPTIMIZATIONS.md).

### Future Optimizations

ZProxy has a roadmap for future optimizations:

- **IO Uring Integration**: Leverage Linux's io_uring for asynchronous I/O
- **QUIC and HTTP/3 Support**: Add support for the latest web protocols
- **Kernel TLS Offloading**: Offload TLS processing to the kernel
- **Hardware Acceleration**: Support for DPDK and TCP offload engines
- **Adaptive Resource Management**: Dynamic adjustment based on workload

For the complete roadmap of future optimizations, see [NEXT_STEPS.md](NEXT_STEPS.md).

### Middleware Architecture

ZProxy's middleware system is designed to be extensible and flexible, following Zig's idiomatic approach:

1. **Compile-time Middleware Chain**: Middleware types are defined at compile time for better type safety
   ```zig
   const MyChain = gateway.middleware.chain.StaticChain(.{
       LoggingMiddleware,
       AuthMiddleware,
   });
   ```

2. **Explicit Configuration**: Each middleware has explicit configuration types
   ```zig
   const configs = .{
       .{ .prefix = "ZPROXY" },  // LoggingMiddleware config
       .{ .jwt_secret = "secret" },  // AuthMiddleware config
   };
   ```

3. **Middleware Interface**: All middleware implements a common interface with:
   - `init(allocator, config)`: Initialize the middleware with configuration
   - `process(context)`: Process a request
   - `deinit()`: Clean up resources

4. **Middleware Chain**: Middleware is executed in a chain, with each middleware having the opportunity to:
   - Modify the request before passing it to the next middleware
   - Reject the request with a custom status code and message
   - Modify the response after the next middleware has processed it
   - Perform actions before and after the request is processed

5. **Custom Middleware**: Users can create their own middleware to extend ZProxy's functionality

This architecture leverages Zig's powerful compile-time features for better type safety and performance, while still providing the flexibility of a middleware pipeline.

For a detailed architecture overview, see [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## API Reference

ZProxy provides a simple API for creating and configuring the gateway. The main components are:

- **Gateway**: The main gateway instance
- **Config**: Configuration for the gateway
- **Route**: Route configuration
- **Middleware**: Middleware components (auth, rate limiting, caching)

For a complete API reference, see [API.md](docs/API.md).

## Examples

The `examples` directory contains example configurations:

- **basic.zig**: A simple gateway with a single route
  ```bash
  zig build run-basic
  ```

- **advanced.zig**: A more complex gateway with multiple routes and middleware
  ```bash
  zig build run-advanced
  ```

- **custom_middleware.zig**: Demonstrates how to create and use custom middleware (coming soon)

  This example shows:
  - How to create a custom logging middleware
  - How to register middleware with the registry
  - How to use custom middleware alongside built-in middleware
  - How to configure middleware with custom options

  ```zig
  // Example custom middleware usage
  const LoggingMiddleware = struct {
      // Implementation details...
  };

  // Register and use the middleware
  try gateway.middleware.registry.register("logging", LoggingMiddleware.create);

  // Create routes that use the middleware
  var routes = try allocator.alloc(gateway.config.Route, 2);
  routes[0] = try gateway.config.Route.init(
      allocator,
      "/api/public",
      "http://localhost:3000",
      &[_][]const u8{ "GET" },
      &[_][]const u8{ "logging" }, // Use custom middleware
  );
  routes[1] = try gateway.config.Route.init(
      allocator,
      "/api/users",
      "http://localhost:3001",
      &[_][]const u8{ "GET", "POST" },
      &[_][]const u8{ "logging", "jwt" }, // Combine custom and built-in middleware
  );
  ```

  Note: This example is currently in development and will be available in a future release.

- **static_middleware.zig**: Demonstrates a compile-time middleware chain

  This example shows:
  - Creating custom middleware
  - Using compile-time middleware chains
  - Configuring multiple routes
  - Setting up different upstream services
  - Using a clean, Zig-idiomatic approach

  ```zig
  // Define a custom middleware
  const LoggingMiddleware = struct {
      prefix: []const u8,
      allocator: std.mem.Allocator,

      pub fn init(allocator: std.mem.Allocator, config: struct { prefix: []const u8 }) !@This() {
          return .{
              .allocator = allocator,
              .prefix = try allocator.dupe(u8, config.prefix),
          };
      }

      pub fn process(self: *const @This(), context: *gateway.middleware.types.Context) !gateway.middleware.types.MiddlewareResult {
          // Log the request
          std.log.info("[{s}] Request: {s} {s}", .{
              self.prefix,
              context.request.method,
              context.request.path,
          });

          return .{ .success = true, .status_code = 200, .error_message = "" };
      }

      pub fn deinit(self: *const @This()) void {
          self.allocator.free(self.prefix);
      }
  };

  // Define middleware chain at compile time
  const MyChain = gateway.middleware.chain.StaticChain(.{LoggingMiddleware});

  // Create configuration for the middleware
  const configs = .{.{ .prefix = "ZPROXY" }};

  // Initialize the middleware chain
  var chain = try MyChain.init(allocator, configs);
  ```

  Run with:
  ```bash
  zig build run-static-middleware
  ```

## Project Structure

```
zproxy/
├── src/                  # Source code
│   ├── config/           # Configuration
│   ├── middleware/       # Middleware components
│   │   ├── auth/         # Authentication middleware
│   │   └── cache/        # Caching middleware
│   ├── protocol/         # Protocol handlers
│   │   ├── http1/        # HTTP/1.1 protocol
│   │   ├── http2/        # HTTP/2 protocol
│   │   └── websocket/    # WebSocket protocol
│   ├── router/           # Routing
│   ├── tls/              # TLS support
│   ├── metrics/          # Metrics collection
│   └── utils/            # Utility functions
│       ├── thread_pool.zig  # NUMA-aware thread pool
│       ├── numa.zig         # NUMA utilities
│       ├── acceptor.zig     # High-performance connection acceptor
│       ├── vectored_io.zig  # Vectored I/O implementation
│       ├── zero_copy.zig    # Zero-copy buffer implementation
│       └── buffer.zig       # Buffer pool implementation
├── examples/             # Example configurations
├── tools/                # Tools and utilities
│   ├── connection_benchmark.zig  # Connection benchmark tool
│   └── run_benchmark.sh          # Automated benchmark script
├── tests/                # Tests
│   ├── unit/             # Unit tests
│   └── integration/      # Integration tests
├── docs/                 # Documentation
├── PERFORMANCE.md        # Performance benchmarks and optimizations
├── OPTIMIZATIONS.md      # Technical deep dive into optimizations
├── NEXT_STEPS.md         # Roadmap for future optimizations
└── BENCHMARK.md          # Benchmarking instructions
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Benchmarking

ZProxy includes a comprehensive benchmarking tool to measure its connection handling capacity:

```bash
# Build the benchmark tool
zig build -Doptimize=ReleaseFast

# Run a basic benchmark
./zig-out/bin/connection_benchmark --host 127.0.0.1 --port 8080

# Run a high concurrency test
./zig-out/bin/connection_benchmark --concurrency 10000 --duration 60

# Use the automated benchmark script
./tools/run_benchmark.sh --host 127.0.0.1 --port 8080
```

The benchmark tool measures:
- Connection rate (connections per second)
- Connection latency (min, avg, max)
- Success rate
- Connection time distribution

For detailed benchmarking instructions, see [BENCHMARK.md](BENCHMARK.md).

## Acknowledgments

- The Zig programming language and community
- Inspiration from other API gateways like NGINX, Kong, and Traefik
