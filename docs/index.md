# ZProxy Documentation

Welcome to the ZProxy documentation. This documentation provides comprehensive information about the ZProxy project, its architecture, components, and how to use it.

## Overview

ZProxy is a high-performance reverse proxy written in Zig, designed to be the fastest proxy ever. It supports HTTP/1.1, HTTP/2, and WebSocket protocols with a focus on performance, memory safety, and simplicity.

## Table of Contents

1. [Getting Started](getting_started.md)
2. [Architecture](architecture.md)
3. [Configuration](config/index.md)
4. [Server](server/index.md)
5. [Protocols](protocol/index.md)
6. [Routing](router/index.md)
7. [Proxying](proxy/index.md)
8. [Middleware](middleware/index.md)
9. [TLS Support](tls/index.md)
10. [Utilities](utils/index.md)
11. [Performance Reports](reports/index.md)
12. [Contributing](contributing.md)

## Project Structure

```
zproxy/
├── src/                  # Source code
│   ├── main.zig          # Entry point
│   ├── config/           # Configuration
│   │   ├── config.zig    # Configuration schema
│   │   └── loader.zig    # Configuration loader
│   ├── server/           # Server implementation
│   │   ├── server.zig    # Base server
│   │   ├── connection.zig # Connection handling
│   │   └── thread_pool.zig # Thread pool
│   ├── protocol/         # Protocol handlers
│   │   ├── detector.zig  # Protocol detection
│   │   ├── http1.zig     # HTTP/1.1 handler
│   │   ├── http2.zig     # HTTP/2 handler
│   │   └── websocket.zig # WebSocket handler
│   ├── router/           # Routing
│   │   ├── router.zig    # Router implementation
│   │   ├── matcher.zig   # Route matching
│   │   └── route.zig     # Route definition
│   ├── proxy/            # Proxying
│   │   ├── proxy.zig     # Proxy implementation
│   │   ├── upstream.zig  # Upstream management
│   │   └── pool.zig      # Connection pooling
│   ├── middleware/       # Middleware
│   │   ├── middleware.zig # Middleware interface
│   │   ├── auth.zig      # Authentication
│   │   ├── rate_limit.zig # Rate limiting
│   │   ├── cors.zig      # CORS handling
│   │   └── cache.zig     # Response caching
│   ├── tls/              # TLS support
│   │   ├── tls.zig       # TLS implementation
│   │   └── certificate.zig # Certificate management
│   └── utils/            # Utilities
│       ├── logger.zig    # Logging
│       ├── buffer.zig    # Buffer management
│       ├── allocator.zig # Custom allocators
│       └── numa.zig      # NUMA utilities
├── tests/                # Tests
├── benchmarks/           # Benchmarks
├── examples/             # Example configurations
└── docs/                 # Documentation
```

## Key Features

- **Multi-Protocol Support**: HTTP/1.1, HTTP/2, and WebSocket protocols
- **High Performance**: Optimized for maximum throughput and minimal latency
- **Flexible Routing**: Path-based routing with support for various HTTP methods
- **Middleware System**: Pluggable middleware for authentication, rate limiting, CORS, and caching
- **TLS Support**: Secure connections with certificate management
- **Thread-per-Connection Model**: Efficient handling of concurrent connections
- **Memory Safety**: Built with Zig's memory safety features
- **Protocol Detection**: Automatic detection of HTTP/1.1, HTTP/2, and WebSocket protocols
- **Connection Pooling**: Reuse connections to upstream servers for better performance
- **Comprehensive Benchmarking**: Built-in tools to measure and compare performance
- **NUMA Awareness**: Optimized for multi-socket systems
- **Custom Allocators**: Fine-grained memory management for performance-critical paths
- **Extensible Architecture**: Easy to add new middleware and protocol handlers
