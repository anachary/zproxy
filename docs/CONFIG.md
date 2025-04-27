# ZProxy Configuration Guide

This document provides detailed information about configuring ZProxy.

## Configuration Methods

ZProxy can be configured in two ways:

1. **Programmatic Configuration**: Create and configure the gateway in Zig code
2. **JSON Configuration**: Load configuration from a JSON file (coming soon)

## Programmatic Configuration

### Basic Configuration

```zig
// Create configuration
var config = try gateway.config.Config.init(allocator);
defer config.deinit();

// Configure listen address and port
allocator.free(config.listen_address);
config.listen_address = try allocator.dupe(u8, "0.0.0.0");
config.listen_port = 8080;
```

### TLS Configuration

```zig
// Enable TLS
config.tls.enabled = true;
config.tls.cert_path = try allocator.dupe(u8, "/path/to/cert.pem");
config.tls.key_path = try allocator.dupe(u8, "/path/to/key.pem");
```

### Middleware Configuration

#### Rate Limiting

```zig
// Configure rate limiting
config.middleware.rate_limit.enabled = true;
config.middleware.rate_limit.requests_per_minute = 100;
```

#### Authentication

```zig
// Configure JWT authentication
config.middleware.auth.enabled = true;
config.middleware.auth.jwt_secret = try allocator.dupe(u8, "your-secret-key");
```

#### Caching

```zig
// Configure response caching
config.middleware.cache.enabled = true;
config.middleware.cache.ttl_seconds = 300;
```

### Routes Configuration

```zig
// Create routes
var routes = try allocator.alloc(gateway.config.Route, 3);

// Users API route with authentication
routes[0] = try gateway.config.Route.init(
    allocator,
    "/api/users",
    "http://users-service:8080",
    &[_][]const u8{ "GET", "POST", "PUT", "DELETE" },
    &[_][]const u8{ "jwt", "ratelimit" },
);

// Products API route with caching
routes[1] = try gateway.config.Route.init(
    allocator,
    "/api/products",
    "http://products-service:8080",
    &[_][]const u8{ "GET" },
    &[_][]const u8{ "cache" },
);

// Public API route
routes[2] = try gateway.config.Route.init(
    allocator,
    "/api/public",
    "http://public-service:8080",
    &[_][]const u8{ "GET" },
    &[_][]const u8{},
);

config.routes = routes;
```

## JSON Configuration (Coming Soon)

In the future, ZProxy will support loading configuration from a JSON file. Here's an example of what the configuration file might look like:

```json
{
  "listen_address": "0.0.0.0",
  "listen_port": 8080,
  "routes": [
    {
      "path": "/api/users",
      "upstream": "http://users-service:8080",
      "methods": ["GET", "POST", "PUT", "DELETE"],
      "middleware": ["jwt", "ratelimit"]
    },
    {
      "path": "/api/products",
      "upstream": "http://products-service:8080",
      "methods": ["GET"],
      "middleware": ["cache"]
    }
  ],
  "tls": {
    "enabled": false,
    "cert_path": "/path/to/cert.pem",
    "key_path": "/path/to/key.pem"
  },
  "middleware": {
    "rate_limit": {
      "enabled": true,
      "requests_per_minute": 100
    },
    "auth": {
      "enabled": true,
      "jwt_secret": "your-secret-key"
    },
    "cache": {
      "enabled": true,
      "ttl_seconds": 300
    }
  }
}
```

## Configuration Options Reference

### Basic Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `listen_address` | `[]const u8` | `"127.0.0.1"` | IP address to listen on |
| `listen_port` | `u16` | `8080` | Port to listen on |

### TLS Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | `bool` | `false` | Whether TLS is enabled |
| `cert_path` | `[]const u8` | `""` | Path to the TLS certificate file |
| `key_path` | `[]const u8` | `""` | Path to the TLS key file |

### Middleware Configuration

#### Rate Limiting

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | `bool` | `false` | Whether rate limiting is enabled |
| `requests_per_minute` | `u32` | `60` | Maximum requests per minute |

#### Authentication

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | `bool` | `false` | Whether JWT authentication is enabled |
| `jwt_secret` | `[]const u8` | `""` | Secret key for JWT validation |

#### Caching

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | `bool` | `false` | Whether response caching is enabled |
| `ttl_seconds` | `u32` | `60` | Time-to-live for cached responses in seconds |

### Route Configuration

| Option | Type | Description |
|--------|------|-------------|
| `path` | `[]const u8` | URL path to match |
| `upstream` | `[]const u8` | Upstream server URL to proxy requests to |
| `methods` | `[]const []const u8` | Allowed HTTP methods (GET, POST, PUT, DELETE, etc.) |
| `middleware` | `[]const []const u8` | List of middleware to apply to this route |

## Path Matching

ZProxy supports path matching with parameters and wildcards:

- **Exact Matching**: `/api/users` matches only `/api/users`
- **Parameter Matching**: `/api/users/:id` matches `/api/users/123`, `/api/users/456`, etc.
- **Wildcard Matching**: `/api/*` matches any path starting with `/api/`

## Middleware Types

ZProxy supports the following middleware types:

- **jwt**: JWT authentication middleware
- **ratelimit**: Rate limiting middleware
- **cache**: Response caching middleware

## Example Configurations

See the [examples](../examples) directory for complete configuration examples.
