# ZProxy Quick Start Guide

This guide provides simple, step-by-step instructions for getting started with ZProxy.

## Prerequisites

- Zig 0.11.0 or later

## Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/zproxy.git
   cd zproxy
   ```

2. Build the project:
   ```bash
   zig build
   ```

## Running ZProxy

### Using the Default Configuration

1. Create a `config.json` file in the root directory:
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
       },
       {
         "path": "/api/products",
         "upstream": "http://localhost:3001",
         "methods": ["GET"],
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

## Testing ZProxy

Once ZProxy is running, you can test it using curl or any HTTP client:

```bash
# Test a route
curl http://localhost:8080/api/users
```

## Common Use Cases

### Simple Reverse Proxy

```json
{
  "listen_address": "127.0.0.1",
  "listen_port": 8080,
  "routes": [
    {
      "path": "/api",
      "upstream": "http://localhost:3000",
      "methods": ["GET", "POST", "PUT", "DELETE"],
      "middleware": []
    }
  ]
}
```

### Multiple Services

```json
{
  "listen_address": "127.0.0.1",
  "listen_port": 8080,
  "routes": [
    {
      "path": "/api/users",
      "upstream": "http://users-service:8080",
      "methods": ["GET", "POST", "PUT", "DELETE"],
      "middleware": []
    },
    {
      "path": "/api/products",
      "upstream": "http://products-service:8080",
      "methods": ["GET"],
      "middleware": []
    }
  ]
}
```

### With Rate Limiting

```json
{
  "listen_address": "127.0.0.1",
  "listen_port": 8080,
  "routes": [
    {
      "path": "/api",
      "upstream": "http://localhost:3000",
      "methods": ["GET", "POST", "PUT", "DELETE"],
      "middleware": ["ratelimit"]
    }
  ],
  "middleware": {
    "rate_limit": {
      "enabled": true,
      "requests_per_minute": 100
    }
  }
}
```

## Troubleshooting

### Common Issues

1. **ZProxy fails to start**
   - Check if the port is already in use
   - Verify that the config.json file is valid JSON
   - Ensure all upstream services are correctly configured

2. **Routes not matching**
   - Check the path configuration in your routes
   - Ensure the HTTP methods match what you're testing with

3. **Compilation errors**
   - Make sure you're using Zig 0.11.0 or later
   - Try cleaning the build with `zig build --clean`

### Getting Help

If you encounter issues not covered here, please:
1. Check the [documentation](docs/)
2. Open an issue on GitHub

## Next Steps

- Read the [full documentation](README.md)
- Explore [custom middleware](docs/CUSTOM_MIDDLEWARE.md)
- Learn about [performance optimizations](OPTIMIZATIONS.md)
