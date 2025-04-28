# ZProxy - The Fastest Proxy Ever

ZProxy is a high-performance reverse proxy written in Zig, designed to be the fastest proxy ever. It supports HTTP/1.1, HTTP/2, and WebSocket protocols with a focus on performance, memory safety, and simplicity.

![ZProxy Logo](docs/images/zproxy_logo.png)

## Overview

ZProxy aims to outperform existing proxy solutions by leveraging Zig's performance characteristics and memory safety features. The architecture is designed for enterprise-level deployments, with support for scaling to 10,000+ connections per second.

## Features

### Core Features
- **Multi-Protocol Support**: HTTP/1.1, HTTP/2, and WebSocket protocols
- **High Performance**: Optimized for maximum throughput and minimal latency
- **Flexible Routing**: Path-based routing with support for various HTTP methods
- **Middleware System**: Pluggable middleware for authentication, rate limiting, CORS, and caching
- **TLS Support**: Secure connections with certificate management
- **Thread-per-Connection Model**: Efficient handling of concurrent connections
- **Memory Safety**: Built with Zig's memory safety features

### Advanced Features
- **Protocol Detection**: Automatic detection of HTTP/1.1, HTTP/2, and WebSocket protocols
- **Connection Pooling**: Reuse connections to upstream servers for better performance
- **Comprehensive Benchmarking**: Built-in tools to measure and compare performance
- **NUMA Awareness**: Optimized for multi-socket systems
- **Custom Allocators**: Fine-grained memory management for performance-critical paths
- **Extensible Architecture**: Easy to add new middleware and protocol handlers

## Getting Started

### Prerequisites

- Zig 0.11.0 or later
- PowerShell 5.0 or later (for running scripts on Windows)

### Building

```bash
# Clone the repository
git clone https://github.com/yourusername/zproxy.git
cd zproxy

# Build the project
zig build

# Run tests
zig build test
```

### Running

```bash
# Run with default configuration
zig build run

# Run with a specific configuration file
zig build run -- examples/basic_proxy.json
```

### Using PowerShell Scripts

ZProxy includes several PowerShell scripts to simplify common tasks:

```powershell
# Start the server with a configuration file
.\scripts\start_server.ps1 -ConfigFile examples/basic_proxy.json

# Run benchmarks
.\scripts\run_benchmark.ps1 -Url "http://localhost:8000/" -Connections 10000 -Duration 30

# Compare ZProxy with other proxies (Nginx, Envoy)
.\scripts\compare_proxies.ps1 -ConfigFile examples/high_performance.json

# Run all benchmarks and generate a report
.\scripts\run_all_benchmarks.ps1 -ConfigFile examples/basic_proxy.json -GenerateReport
```

### Benchmarking

ZProxy includes a comprehensive benchmarking system:

```bash
# Run HTTP/1.1 benchmarks
zig build benchmark -- http://localhost:8000/ 10000 30 100 1 http1

# Run HTTP/2 benchmarks
zig build benchmark -- http://localhost:8000/ 10000 30 100 1 http2

# Run WebSocket benchmarks
zig build benchmark -- ws://localhost:8000/ 1000 30 100 0 websocket
```

Parameters:
- URL
- Number of connections
- Duration in seconds
- Concurrency level
- Keep-alive (1=enabled, 0=disabled)
- Protocol (http1, http2, websocket)

## Configuration

ZProxy is configured using a JSON file. Several example configurations are provided in the `examples/` directory.

### Basic Configuration

```json
{
  "host": "0.0.0.0",
  "port": 8000,
  "thread_count": 4,
  "backlog": 128,
  "max_connections": 1000,
  "connection_timeout_ms": 30000,
  "protocols": ["http1", "http2", "websocket"],
  "tls": {
    "enabled": false,
    "cert_file": null,
    "key_file": null
  },
  "routes": [
    {
      "path": "/api",
      "upstream": "http://localhost:8080",
      "methods": ["GET", "POST", "PUT", "DELETE"]
    },
    {
      "path": "/static",
      "upstream": "http://localhost:8081",
      "methods": ["GET"]
    },
    {
      "path": "/",
      "upstream": "http://localhost:8082",
      "methods": ["GET", "POST"]
    }
  ],
  "middlewares": []
}
```

### Configuration with Middleware

```json
{
  "host": "0.0.0.0",
  "port": 8000,
  "thread_count": 4,
  "backlog": 128,
  "max_connections": 1000,
  "connection_timeout_ms": 30000,
  "protocols": ["http1", "http2", "websocket"],
  "tls": {
    "enabled": false,
    "cert_file": null,
    "key_file": null
  },
  "routes": [
    {
      "path": "/api",
      "upstream": "http://localhost:8080",
      "methods": ["GET", "POST", "PUT", "DELETE"]
    }
  ],
  "middlewares": [
    {
      "type": "rate_limit",
      "config": {
        "requests_per_minute": 100
      }
    },
    {
      "type": "cors",
      "config": {
        "allowed_origins": ["*"],
        "allow_credentials": true
      }
    },
    {
      "type": "cache",
      "config": {
        "ttl_seconds": 300
      }
    }
  ]
}
```

### High-Performance Configuration

```json
{
  "host": "0.0.0.0",
  "port": 8000,
  "thread_count": 16,
  "backlog": 1024,
  "max_connections": 10000,
  "connection_timeout_ms": 30000,
  "protocols": ["http1", "http2"],
  "tls": {
    "enabled": false,
    "cert_file": null,
    "key_file": null
  },
  "routes": [
    {
      "path": "/api",
      "upstream": "http://localhost:8080",
      "methods": ["GET", "POST", "PUT", "DELETE"]
    }
  ],
  "middlewares": []
}
```

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
    ├── config/           # Configuration documentation
    ├── server/           # Server documentation
    ├── protocol/         # Protocol documentation
    ├── router/           # Router documentation
    ├── proxy/            # Proxy documentation
    ├── middleware/       # Middleware documentation
    ├── tls/              # TLS documentation
    ├── utils/            # Utilities documentation
    └── reports/          # Performance reports
```

## Performance

ZProxy is designed to be the fastest proxy ever, with a focus on:

- **Low Latency**: Minimal processing overhead with optimized code paths
- **High Throughput**: Efficient handling of concurrent connections (10,000+ connections per second)
- **Memory Efficiency**: Careful memory management with custom allocators
- **CPU Efficiency**: Optimized algorithms and data structures
- **Scalability**: Designed to scale across multiple CPU cores and NUMA nodes

### Benchmarking

The benchmarking system allows you to:

1. **Measure Performance**: Quantify requests per second, latency, and throughput
2. **Compare Configurations**: Test different configuration settings
3. **Compare Protocols**: Benchmark HTTP/1.1, HTTP/2, and WebSocket
4. **Compare with Other Proxies**: Benchmark against Nginx, Envoy, and other proxies

Benchmark reports are generated in Markdown format and stored in the `docs/reports/` directory.

## Documentation

ZProxy includes comprehensive documentation in the `docs` directory:

- [Getting Started](docs/getting_started.md)
- [Architecture](docs/architecture.md)
- [Configuration](docs/config/index.md)
- [Server](docs/server/index.md)
- [Protocols](docs/protocol/index.md)
- [Routing](docs/router/index.md)
- [Proxying](docs/proxy/index.md)
- [Middleware](docs/middleware/index.md)
- [TLS Support](docs/tls/index.md)
- [Utilities](docs/utils/index.md)
- [Performance Reports](docs/reports/index.md)
- [Contributing](docs/contributing.md)

## Development

### Architecture

ZProxy follows a modular architecture with clear separation of concerns:

1. **Configuration**: JSON-based configuration with validation
2. **Server**: Core server implementation with connection handling
3. **Protocol Handlers**: Protocol-specific implementations
4. **Router**: Request routing based on paths and methods
5. **Proxy**: Forwarding requests to upstream servers
6. **Middleware**: Pluggable components for request/response processing
7. **TLS**: Secure connection handling
8. **Utilities**: Logging, buffer management, and other utilities

### Contributing

Contributions are welcome! Here's how you can contribute:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`zig build test`)
5. Commit your changes (`git commit -m 'Add some amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
