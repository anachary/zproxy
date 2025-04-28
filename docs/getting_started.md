# Getting Started with ZProxy

This guide will help you get started with ZProxy, a high-performance reverse proxy written in Zig.

## Prerequisites

Before you begin, make sure you have the following installed:

- [Zig](https://ziglang.org/download/) 0.11.0 or later
- [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell) 5.0 or later (for running scripts on Windows)

## Installation

### Clone the Repository

```bash
git clone https://github.com/yourusername/zproxy.git
cd zproxy
```

### Build ZProxy

```bash
zig build
```

This will build the ZProxy executable and place it in the `zig-out/bin` directory.

## Basic Usage

### Create a Configuration File

ZProxy is configured using a JSON file. Here's a basic example:

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

Save this to a file, e.g., `config.json`.

### Run ZProxy

```bash
zig build run -- config.json
```

Or, if you've already built ZProxy:

```bash
./zig-out/bin/zproxy config.json
```

ZProxy will start and listen on the configured host and port.

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

## Configuration

ZProxy is configured using a JSON file. The configuration file has the following sections:

### Server Configuration

```json
{
  "host": "0.0.0.0",
  "port": 8000,
  "thread_count": 4,
  "backlog": 128,
  "max_connections": 1000,
  "connection_timeout_ms": 30000
}
```

- `host`: The host to listen on
- `port`: The port to listen on
- `thread_count`: The number of threads to use
- `backlog`: The maximum number of pending connections
- `max_connections`: The maximum number of concurrent connections
- `connection_timeout_ms`: The connection timeout in milliseconds

### Protocol Configuration

```json
{
  "protocols": ["http1", "http2", "websocket"]
}
```

- `protocols`: An array of enabled protocols

### TLS Configuration

```json
{
  "tls": {
    "enabled": true,
    "cert_file": "cert.pem",
    "key_file": "key.pem"
  }
}
```

- `enabled`: Whether TLS is enabled
- `cert_file`: The path to the certificate file
- `key_file`: The path to the key file

### Route Configuration

```json
{
  "routes": [
    {
      "path": "/api",
      "upstream": "http://localhost:8080",
      "methods": ["GET", "POST", "PUT", "DELETE"]
    }
  ]
}
```

- `path`: The path to match
- `upstream`: The upstream server to proxy to
- `methods`: An array of allowed HTTP methods

### Middleware Configuration

```json
{
  "middlewares": [
    {
      "type": "rate_limit",
      "config": {
        "requests_per_minute": 100
      }
    }
  ]
}
```

- `type`: The type of middleware
- `config`: The middleware configuration

## Example Configurations

ZProxy includes several example configurations in the `examples` directory:

- `basic_proxy.json`: A basic proxy configuration
- `with_middleware.json`: A configuration with middleware
- `with_tls.json`: A configuration with TLS
- `high_performance.json`: A configuration optimized for high performance

## Next Steps

- [Learn about the ZProxy architecture](architecture.md)
- [Explore the configuration options](config/index.md)
- [Learn about the available middleware](middleware/index.md)
- [Run benchmarks](reports/index.md)
