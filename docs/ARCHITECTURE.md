# ZProxy Architecture

This document provides an overview of the ZProxy architecture, explaining the key components and how they interact.

## Overview

ZProxy is designed as a high-performance reverse proxy that routes incoming requests to upstream services based on configurable rules. It supports multiple protocols (HTTP/1.1, HTTP/2, WebSocket) and provides middleware for common functionality like authentication, rate limiting, and caching.

## Components

### Core Components

- **Server**: The main entry point that handles incoming connections and manages the lifecycle of the proxy.
- **Router**: Matches incoming requests to routes and applies middleware.
- **Protocol Handlers**: Detect and handle different protocols (HTTP/1.1, HTTP/2, WebSocket).
- **Configuration**: Manages proxy configuration from files or code.

### Protocol Handling

The proxy supports multiple protocols:

1. **HTTP/1.1**: Standard HTTP protocol with support for all HTTP methods.
2. **HTTP/2**: Modern HTTP protocol with multiplexing and header compression.
3. **WebSocket**: Protocol for bidirectional communication over a single TCP connection.

The protocol detector examines the initial bytes of a connection to determine which protocol is being used, then hands off the connection to the appropriate handler.

### Routing

The router matches incoming requests to routes based on the URL path and HTTP method. It supports:

- **Path Parameters**: Match dynamic parts of a URL (e.g., `/api/users/:id`).
- **Wildcards**: Match any path under a prefix (e.g., `/api/*`).
- **Method Matching**: Only allow specific HTTP methods for a route.

### Middleware

The middleware system processes requests before they are forwarded to upstream services. It supports:

- **Authentication**: Verify API keys or other credentials.
- **Rate Limiting**: Limit the number of requests from a client.
- **CORS**: Handle Cross-Origin Resource Sharing.
- **Caching**: Cache responses to improve performance.

### TLS

The proxy supports TLS for secure connections:

- **Certificate Management**: Loads and manages TLS certificates.
- **SNI Support**: Uses different certificates for different domains.

## Data Flow

1. A client connects to the proxy.
2. The protocol detector identifies the protocol being used.
3. The protocol handler parses the request.
4. The router finds a matching route for the request.
5. Middleware is applied to the request.
6. If middleware allows the request, it is proxied to the upstream service.
7. The response from the upstream service is returned to the client.

## Concurrency Model

The proxy uses a thread-per-connection model for handling requests:

1. The main thread accepts new connections.
2. Each connection is handled in a separate thread.
3. Thread pools and connection pools are used to manage resources efficiently.

## Error Handling

The proxy handles errors at different levels:

- **Protocol Errors**: Invalid requests are rejected with appropriate status codes.
- **Routing Errors**: Requests that don't match any route receive a 404 response.
- **Upstream Errors**: Errors from upstream services are logged and proxied back to the client.
- **Proxy Errors**: Internal errors are logged and result in a 500 response.

## Extensibility

The proxy is designed to be extensible:

- **Middleware**: New middleware can be added by implementing the middleware interface.
- **Protocol Extensions**: Support for new protocols can be added by implementing a protocol handler.
- **Configuration Extensions**: The configuration system can be extended to support new options.

## Performance Optimizations

The proxy includes several performance optimizations:

- **Zero-Copy**: Minimizes memory copying for better performance.
- **Buffer Pooling**: Reuses buffers to reduce memory allocations.
- **Connection Pooling**: Maintains connections to upstream services.
- **NUMA Awareness**: Optimizes for multi-socket systems.

## Configuration

The proxy is configured using a JSON file that specifies:

- **Server Settings**: Host, port, thread count, etc.
- **Protocol Settings**: Enabled protocols and their options.
- **TLS Settings**: Certificate and key files.
- **Routes**: Path patterns, upstream services, and allowed methods.
- **Middleware**: Middleware configuration for authentication, rate limiting, etc.

## Deployment

The proxy can be deployed in various ways:

- **Standalone**: Run as a standalone service.
- **Docker**: Run in a Docker container.
- **Kubernetes**: Deploy as part of a Kubernetes cluster.

## Monitoring

The proxy provides monitoring through:

- **Logging**: Detailed logs for debugging and auditing.
- **Metrics**: Performance metrics for monitoring.
- **Health Checks**: Endpoints for checking the proxy's health.

## Future Enhancements

Planned enhancements include:

- **HTTP/3 Support**: Add support for the HTTP/3 protocol.
- **Dynamic Configuration**: Allow configuration changes without restarting.
- **Plugin System**: Support for third-party plugins.
- **Advanced Routing**: Support for more complex routing rules.
- **Load Balancing**: Distribute requests across multiple upstream services.
