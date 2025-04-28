# config.zig Documentation

## Overview

The `config.zig` file defines the configuration structures and functions for ZProxy. It handles loading configuration from JSON files and provides default values. The updated version now includes middleware configuration.

## Key Components

### Protocol Enumeration

```zig
pub const Protocol = enum {
    http1,
    http2,
    websocket,
};
```

This enumeration defines the protocols supported by ZProxy:
- `http1`: HTTP/1.1 protocol
- `http2`: HTTP/2 protocol
- `websocket`: WebSocket protocol

### Middleware Configuration

```zig
pub const MiddlewareConfig = struct {
    type: []const u8,
    config: std.json.Value,

    pub fn deinit(self: *MiddlewareConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        // The config value is freed separately
    }
};
```

This structure holds middleware configuration:
- `type`: The type of middleware (e.g., "rate_limit", "auth", "cors", "cache")
- `config`: JSON configuration specific to the middleware type

The `deinit` method ensures proper cleanup of allocated memory.

### TLS Configuration

```zig
pub const TlsConfig = struct {
    enabled: bool,
    cert_file: ?[]const u8,
    key_file: ?[]const u8,

    pub fn deinit(self: *TlsConfig, allocator: std.mem.Allocator) void {
        // Free allocated memory
    }
};
```

This structure holds TLS configuration:
- `enabled`: Whether TLS is enabled
- `cert_file`: Path to the certificate file (optional)
- `key_file`: Path to the key file (optional)

The `deinit` method ensures proper cleanup of allocated memory.

### Route Configuration

```zig
pub const Route = struct {
    path: []const u8,
    upstream: []const u8,
    methods: []const []const u8,

    pub fn deinit(self: *Route, allocator: std.mem.Allocator) void {
        // Free allocated memory
    }
};
```

This structure defines a route:
- `path`: The URL path to match
- `upstream`: The upstream server URL
- `methods`: Allowed HTTP methods

The `deinit` method ensures proper cleanup of allocated memory.

### Main Configuration

```zig
pub const Config = struct {
    // Server configuration
    host: []const u8,
    port: u16,

    // Performance configuration
    thread_count: u32,
    backlog: u32,
    max_connections: u32,
    connection_timeout_ms: u32,

    // Protocol configuration
    protocols: []const Protocol,

    // TLS configuration
    tls: TlsConfig,

    // Routing configuration
    routes: []Route,

    // Middleware configuration
    middlewares: []MiddlewareConfig,

    // Store the allocator for cleanup
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        // Free allocated memory
    }
};
```

This is the main configuration structure that holds all settings for ZProxy:
- Server configuration (host, port)
- Performance settings (thread count, connection limits)
- Protocol settings
- TLS configuration
- Routing configuration
- Middleware configuration

The `deinit` method ensures proper cleanup of all allocated memory.

### Configuration Loading

```zig
pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Config {
    // Load and parse configuration from a JSON file
}
```

This function loads configuration from a JSON file:
1. Opens and reads the file
2. Parses the JSON content
3. Extracts configuration values
4. Allocates memory for strings and arrays
5. Returns a fully initialized `Config` structure

The function now also parses middleware configuration from the JSON file.

### Default Configuration

```zig
pub fn getDefaultConfig(allocator: std.mem.Allocator) Config {
    // Create and return a default configuration
}
```

This function creates a default configuration when no configuration file is provided:
- Listens on 127.0.0.1:8000
- Supports HTTP/1.1
- Has a single route that forwards all requests to 127.0.0.1:8080
- Uses reasonable defaults for performance settings
- Includes an empty middleware configuration

### Testing

```zig
test "Config - Default Configuration" {
    // Test the default configuration
}
```

This test ensures that the default configuration has the expected values, including the new middleware configuration.

## Zig Programming Principles

1. **Memory Management**: The configuration module carefully manages memory, allocating space for strings and arrays and providing `deinit` methods to free that memory.
2. **Error Handling**: Functions that can fail return errors using Zig's error union type.
3. **Optional Values**: The `?` syntax is used for optional values like TLS certificate files.
4. **Testing**: Tests are integrated directly into the code.
5. **Resource Safety**: The code uses `defer` statements to ensure resources are properly cleaned up, even if an error occurs.

## Usage Example

```zig
// Load configuration from a file
var config = try config.loadFromFile(allocator, "config.json");
defer config.deinit();

// Or use default configuration
var default_config = config.getDefaultConfig(allocator);
defer default_config.deinit();

// Access middleware configuration
for (config.middlewares) |middleware| {
    logger.info("Middleware: {s}", .{middleware.type});
}
```

## Example JSON Configuration

```json
{
  "host": "0.0.0.0",
  "port": 8000,
  "thread_count": 8,
  "backlog": 256,
  "max_connections": 10000,
  "connection_timeout_ms": 30000,
  "protocols": ["http1", "http2", "websocket"],
  "tls": {
    "enabled": true,
    "cert_file": "cert.pem",
    "key_file": "key.pem"
  },
  "routes": [
    {
      "path": "/api/users",
      "upstream": "http://users-service:8080",
      "methods": ["GET", "POST", "PUT", "DELETE"]
    },
    {
      "path": "/api/products",
      "upstream": "http://products-service:8080",
      "methods": ["GET", "POST"]
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
      "type": "auth",
      "config": {
        "api_keys": ["key1", "key2"]
      }
    },
    {
      "type": "cors",
      "config": {
        "allowed_origins": ["https://example.com", "https://api.example.com"],
        "allow_credentials": true
      }
    }
  ]
}
