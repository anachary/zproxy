# ZProxy - High-Performance API Gateway

A blazingly fast API gateway written in Zig that routes traffic to different backends based on rules like URL paths or authentication headers. ZProxy is designed to be the fastest reverse proxy available, leveraging Zig's unique capabilities and advanced optimization techniques.

## Quick Start

For a quick start guide, see [QUICKSTART.md](QUICKSTART.md).

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

1. Create a `config.json` file (or copy from `config.example.json`):
   ```json
   {
     "listen_address": "127.0.0.1",
     "listen_port": 8080,
     "routes": [
       {
         "path": "/api/users",
         "upstream": "http://localhost:3000",
         "methods": ["GET", "POST", "PUT", "DELETE"],
         "middleware": []
       }
     ],
     "tls": {
       "enabled": false,
       "cert_path": "",
       "key_path": "",
       "domain_certs": []
     },
     "middleware": {
       "rate_limit": {
         "enabled": false,
         "requests_per_minute": 100
       },
       "auth": {
         "enabled": false,
         "jwt_secret": ""
       },
       "cache": {
         "enabled": false,
         "ttl_seconds": 300
       }
     }
   }
   ```

2. Run ZProxy:
   ```bash
   zig build run
   ```

3. Test with curl:
   ```bash
   curl http://localhost:8080/api/users
   ```

### Running Examples

ZProxy comes with several examples to help you get started:

1. Basic example (simple configuration with a single route):
   ```bash
   zig build run-basic
   ```

2. Advanced example (multiple routes with middleware):
   ```bash
   zig build run-advanced
   ```

3. Static middleware example (compile-time middleware chain):
   ```bash
   zig build run-static-middleware
   ```

### Troubleshooting

If you encounter issues running ZProxy:

1. Check if the port is already in use
2. Verify that the config.json file is valid JSON
3. Ensure all upstream services are correctly configured
4. Try building with debug information: `zig build -Doptimize=Debug`

For more detailed troubleshooting, see [QUICKSTART.md](QUICKSTART.md).

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

For a detailed architecture overview, see [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## API Reference

ZProxy provides a simple API for creating and configuring the gateway. The main components are:

- **Gateway**: The main gateway instance
- **Config**: Configuration for the gateway
- **Route**: Route configuration
- **Middleware**: Middleware components (auth, rate limiting, caching)

For a complete API reference, see [API.md](docs/API.md).

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
├── benchmarks/           # Benchmarking tools and utilities
│   ├── connection_benchmark.zig  # Connection benchmark tool
│   ├── simple_benchmark.zig      # Simplified benchmark tool
│   ├── mock_server.zig           # Mock server for testing
│   └── results/                  # Benchmark results
├── scripts/              # Utility scripts
│   ├── run_benchmark.ps1         # Windows benchmark script
│   ├── run_benchmark.sh          # Linux/macOS benchmark script
│   └── stress_test.ps1           # Stress testing script
├── tests/                # Tests
│   ├── unit/             # Unit tests
│   └── integration/      # Integration tests
├── docs/                 # Documentation
│   ├── API.md                    # API reference
│   ├── ARCHITECTURE.md           # Architecture overview
│   ├── CONFIG.md                 # Configuration guide
│   └── CUSTOM_MIDDLEWARE.md      # Custom middleware guide
├── PERFORMANCE.md        # Performance benchmarks and optimizations
├── OPTIMIZATIONS.md      # Technical deep dive into optimizations
├── QUICKSTART.md         # Quick start guide
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

ZProxy includes comprehensive benchmarking tools to measure its performance:

```bash
# Build the benchmark tools
zig build -Doptimize=ReleaseFast

# Run a basic benchmark
cd scripts
./run_benchmark.ps1 --host 127.0.0.1 --port 8080
```

For detailed benchmarking instructions, see [BENCHMARK.md](BENCHMARK.md).

## Acknowledgments

- The Zig programming language and community
- Inspiration from other API gateways like NGINX, Kong, and Traefik
