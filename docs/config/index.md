# ZProxy Configuration

This document describes the configuration options for ZProxy.

## Overview

ZProxy is configured using a JSON file that specifies the server settings, routes, and middleware. The configuration is loaded at startup and can be reloaded at runtime.

## Configuration File

The configuration file is a JSON file with the following structure:

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
    }
  ]
}
```

## Configuration Options

### Server Configuration

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `host` | string | `"0.0.0.0"` | The host to listen on |
| `port` | integer | `8000` | The port to listen on |
| `thread_count` | integer | `4` | The number of threads to use |
| `backlog` | integer | `128` | The maximum number of pending connections |
| `max_connections` | integer | `1000` | The maximum number of concurrent connections |
| `connection_timeout_ms` | integer | `30000` | The connection timeout in milliseconds |

### Protocol Configuration

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `protocols` | array | `["http1", "http2", "websocket"]` | An array of enabled protocols |

### TLS Configuration

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `tls.enabled` | boolean | `false` | Whether TLS is enabled |
| `tls.cert_file` | string | `null` | The path to the certificate file |
| `tls.key_file` | string | `null` | The path to the key file |

### Route Configuration

Each route has the following options:

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `path` | string | - | The path to match |
| `upstream` | string | - | The upstream server to proxy to |
| `methods` | array | `["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH"]` | An array of allowed HTTP methods |

### Middleware Configuration

Each middleware has the following options:

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `type` | string | - | The type of middleware |
| `config` | object | - | The middleware configuration |

## Middleware Types

### Rate Limiting

The rate limiting middleware limits the number of requests from a client.

```json
{
  "type": "rate_limit",
  "config": {
    "requests_per_minute": 100
  }
}
```

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `requests_per_minute` | integer | `60` | The maximum number of requests per minute |

### CORS

The CORS middleware handles Cross-Origin Resource Sharing.

```json
{
  "type": "cors",
  "config": {
    "allowed_origins": ["*"],
    "allow_credentials": true
  }
}
```

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `allowed_origins` | array | `["*"]` | An array of allowed origins |
| `allow_credentials` | boolean | `false` | Whether to allow credentials |

### Authentication

The authentication middleware verifies API keys or other credentials.

```json
{
  "type": "auth",
  "config": {
    "api_keys": ["key1", "key2"],
    "header_name": "X-API-Key"
  }
}
```

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `api_keys` | array | - | An array of valid API keys |
| `header_name` | string | `"X-API-Key"` | The name of the header containing the API key |

### Caching

The caching middleware caches responses to improve performance.

```json
{
  "type": "cache",
  "config": {
    "ttl_seconds": 300
  }
}
```

| Option | Type | Default | Description |
| ------ | ---- | ------- | ----------- |
| `ttl_seconds` | integer | `60` | The time-to-live in seconds |

## Example Configurations

### Basic Proxy

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

### With Middleware

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

### With TLS

```json
{
  "host": "0.0.0.0",
  "port": 443,
  "thread_count": 4,
  "backlog": 128,
  "max_connections": 1000,
  "connection_timeout_ms": 30000,
  "protocols": ["http1", "http2", "websocket"],
  "tls": {
    "enabled": true,
    "cert_file": "cert.pem",
    "key_file": "key.pem"
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

### High Performance

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

## Configuration API

ZProxy provides an API for managing the configuration at runtime:

- `GET /config`: Get the current configuration
- `PUT /config`: Update the configuration
- `GET /health`: Check the health of the proxy

## Configuration File Location

The configuration file can be specified as a command-line argument:

```bash
zig build run -- config.json
```

If no configuration file is specified, ZProxy will look for a file named `config.json` in the current directory.
