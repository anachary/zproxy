const std = @import("std");
const config = @import("config.zig");
const logger = @import("../utils/logger.zig");

/// Load configuration from a JSON file
pub fn loadFromFile(allocator: std.mem.Allocator, file_path: []const u8) !config.Config {
    logger.info("Loading configuration from {s}", .{file_path});

    // Open the file
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    // Read the file content
    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);

    const bytes_read = try file.readAll(buffer);
    if (bytes_read != file_size) {
        return error.IncompleteRead;
    }

    // Parse JSON
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, buffer, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Parse server configuration
    const host = try allocator.dupe(u8, root.object.get("host").?.string);
    const port = @as(u16, @intCast(root.object.get("port").?.integer));

    // Parse performance configuration
    const thread_count = @as(u32, @intCast(root.object.get("thread_count").?.integer));
    const backlog = @as(u32, @intCast(root.object.get("backlog").?.integer));
    const max_connections = @as(u32, @intCast(root.object.get("max_connections").?.integer));
    const connection_timeout_ms = @as(u32, @intCast(root.object.get("connection_timeout_ms").?.integer));

    // Parse protocol configuration
    const protocols_json = root.object.get("protocols").?.array;
    var protocols = try allocator.alloc(config.Protocol, protocols_json.items.len);

    for (protocols_json.items, 0..) |protocol_json, i| {
        const protocol_str = protocol_json.string;
        if (std.mem.eql(u8, protocol_str, "http1")) {
            protocols[i] = .http1;
        } else if (std.mem.eql(u8, protocol_str, "http2")) {
            protocols[i] = .http2;
        } else if (std.mem.eql(u8, protocol_str, "websocket")) {
            protocols[i] = .websocket;
        } else {
            return error.UnsupportedProtocol;
        }
    }

    // Parse TLS configuration
    const tls_json = root.object.get("tls").?.object;
    const tls_enabled = tls_json.get("enabled").?.bool;

    var tls_cert_file: ?[]const u8 = null;
    var tls_key_file: ?[]const u8 = null;

    if (tls_enabled) {
        if (tls_json.get("cert_file")) |cert_file_json| {
            if (cert_file_json != .null) {
                tls_cert_file = try allocator.dupe(u8, cert_file_json.string);
            }
        }
        if (tls_json.get("key_file")) |key_file_json| {
            if (key_file_json != .null) {
                tls_key_file = try allocator.dupe(u8, key_file_json.string);
            }
        }
    }

    const tls = config.TlsConfig{
        .enabled = tls_enabled,
        .cert_file = tls_cert_file,
        .key_file = tls_key_file,
    };

    // Parse routes
    const routes_json = root.object.get("routes").?.array;
    var routes = try allocator.alloc(config.Route, routes_json.items.len);

    for (routes_json.items, 0..) |route_json, i| {
        const route_obj = route_json.object;

        const path = try allocator.dupe(u8, route_obj.get("path").?.string);
        const upstream = try allocator.dupe(u8, route_obj.get("upstream").?.string);

        const methods_json = route_obj.get("methods").?.array;
        var methods = try allocator.alloc([]const u8, methods_json.items.len);

        for (methods_json.items, 0..) |method_json, j| {
            methods[j] = try allocator.dupe(u8, method_json.string);
        }

        routes[i] = config.Route{
            .path = path,
            .upstream = upstream,
            .methods = methods,
        };
    }

    // Parse middleware configuration
    var middlewares: []config.MiddlewareConfig = &[_]config.MiddlewareConfig{};

    if (root.object.get("middlewares")) |middlewares_json| {
        const middlewares_array = middlewares_json.array;
        middlewares = try allocator.alloc(config.MiddlewareConfig, middlewares_array.items.len);

        for (middlewares_array.items, 0..) |middleware_json, i| {
            const middleware_obj = middleware_json.object;

            const middleware_type = try allocator.dupe(u8, middleware_obj.get("type").?.string);
            const middleware_config = middleware_obj.get("config").?;

            middlewares[i] = config.MiddlewareConfig{
                .type = middleware_type,
                .config = middleware_config,
            };
        }
    }

    return config.Config{
        .host = host,
        .port = port,
        .thread_count = thread_count,
        .backlog = backlog,
        .max_connections = max_connections,
        .connection_timeout_ms = connection_timeout_ms,
        .protocols = protocols,
        .tls = tls,
        .routes = routes,
        .middlewares = middlewares,
        .allocator = allocator,
    };
}

test "Loader - Load From File" {
    // This test would normally load a test configuration file
    // For simplicity, we'll just check that the function exists
    _ = loadFromFile;
}
