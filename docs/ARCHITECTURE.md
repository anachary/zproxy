# ZProxy Architecture

This document provides an overview of the ZProxy architecture.

## Overview

The gateway is designed as a reverse proxy that routes incoming requests to upstream services based on configurable rules. It supports multiple protocols (HTTP/1.1, HTTP/2, WebSocket) and provides middleware for common functionality like authentication, rate limiting, and caching.

## Components

### Core Components

- **Gateway**: The main entry point that handles incoming connections and manages the lifecycle of the gateway.
- **Router**: Matches incoming requests to routes and applies middleware.
- **Protocol Handlers**: Detect and handle different protocols (HTTP/1.1, HTTP/2, WebSocket).
- **Middleware**: Provides cross-cutting functionality like authentication, rate limiting, and caching.
- **Configuration**: Manages gateway configuration from files or code.

### Protocol Handling

The gateway supports multiple protocols:

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

Middleware provides cross-cutting functionality that can be applied to routes:

- **Authentication**: Validates JWT tokens and enforces access control.
- **Rate Limiting**: Limits the number of requests a client can make in a time period.
- **Caching**: Caches responses to improve performance.

Middleware can be configured globally or per-route.

### TLS

The gateway supports TLS for secure connections:

- **Certificate Management**: Loads and manages TLS certificates.
- **SNI Support**: Uses different certificates for different domains.

### Metrics

The gateway collects metrics to monitor its performance:

- **Request Counters**: Count the number of requests by route, method, and status code.
- **Latency Histograms**: Measure the time taken to process requests.
- **Connection Gauges**: Track the number of active connections.

## Data Flow

1. A client connects to the gateway.
2. The protocol detector identifies the protocol being used.
3. The protocol handler parses the request.
4. The router finds a matching route for the request.
5. Middleware is applied to the request.
6. If middleware allows the request, it is proxied to the upstream service.
7. The response from the upstream service is returned to the client.

## Concurrency Model

The gateway uses a thread-per-connection model for handling requests:

1. The main thread accepts new connections.
2. Each connection is handled in a separate thread.
3. Thread pools and connection pools are used to manage resources efficiently.

## Error Handling

The gateway handles errors at different levels:

- **Protocol Errors**: Invalid requests are rejected with appropriate status codes.
- **Routing Errors**: Requests that don't match any route receive a 404 response.
- **Middleware Errors**: Middleware can reject requests with custom status codes and messages.
- **Upstream Errors**: Errors from upstream services are logged and proxied back to the client.
- **Gateway Errors**: Internal errors are logged and result in a 500 response.

## Extensibility

The gateway is designed to be extensible:

- **Custom Middleware**: New middleware can be added by implementing the middleware interface.
- **Protocol Extensions**: Support for new protocols can be added by implementing a protocol handler.
- **Configuration Extensions**: The configuration system can be extended to support new options.
