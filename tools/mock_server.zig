const std = @import("std");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    const logger = std.log.scoped(.mock_server);
    logger.info("Starting mock server...", .{});

    // Create server with highly optimized options for maximum connections
    const server_options = std.net.StreamServer.Options{
        .reuse_address = true,
        .reuse_port = true,
        .kernel_backlog = 65535, // Maximum backlog
    };

    const address = try std.net.Address.parseIp("127.0.0.1", 8080);
    var server = std.net.StreamServer.init(server_options);
    defer server.deinit();

    try server.listen(address);

    logger.info("Mock server listening on 127.0.0.1:8080", .{});

    // Create a thread pool for handling connections
    // Use more threads than CPU count for high connection loads
    const cpu_count = try std.Thread.getCpuCount();
    const thread_count = cpu_count * 4; // Use 4x CPU count for better handling of high connection loads
    logger.info("Using {d} worker threads (CPU count: {d})", .{ thread_count, cpu_count });

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    // Create a semaphore for signaling new connections
    var connection_semaphore = std.Thread.Semaphore{};

    // Create a queue for connections
    var connection_queue = std.fifo.LinearFifo(std.net.StreamServer.Connection, .Dynamic).init(allocator);
    defer connection_queue.deinit();

    // Create a mutex for the connection queue
    var queue_mutex = std.Thread.Mutex{};

    // Create a flag for shutdown
    var shutdown_requested = std.atomic.Atomic(bool).init(false);

    // Create worker threads
    for (threads, 0..) |*thread, i| {
        const worker_context = try allocator.create(WorkerContext);
        worker_context.* = WorkerContext{
            .allocator = allocator,
            .id = i,
            .connection_queue = &connection_queue,
            .queue_mutex = &queue_mutex,
            .connection_semaphore = &connection_semaphore,
            .shutdown_requested = &shutdown_requested,
        };

        thread.* = try std.Thread.spawn(.{}, workerThread, .{worker_context});
    }

    // Accept connections until interrupted
    while (true) {
        const connection = server.accept() catch |err| {
            if (err == error.ConnectionAborted or
                err == error.ConnectionResetByPeer or
                err == error.WouldBlock)
            {
                // These are common errors, just continue
                continue;
            }
            logger.err("Error accepting connection: {}", .{err});
            continue;
        };

        // Add connection to the queue
        queue_mutex.lock();
        connection_queue.writeItem(connection) catch {
            logger.err("Error adding connection to queue", .{});
            connection.stream.close();
            queue_mutex.unlock();
            continue;
        };
        queue_mutex.unlock();

        // Signal a worker thread
        connection_semaphore.post();
    }
}

const WorkerContext = struct {
    allocator: std.mem.Allocator,
    id: usize,
    connection_queue: *std.fifo.LinearFifo(std.net.StreamServer.Connection, .Dynamic),
    queue_mutex: *std.Thread.Mutex,
    connection_semaphore: *std.Thread.Semaphore,
    shutdown_requested: *std.atomic.Atomic(bool),
};

const ConnectionContext = struct {
    allocator: std.mem.Allocator,
    connection: std.net.StreamServer.Connection,
};

fn workerThread(context: *WorkerContext) !void {
    defer context.allocator.destroy(context);

    const logger = std.log.scoped(.worker);
    logger.debug("Worker thread {d} started", .{context.id});

    while (!context.shutdown_requested.load(.Acquire)) {
        // Wait for a connection
        context.connection_semaphore.wait();

        // Check if shutdown was requested
        if (context.shutdown_requested.load(.Acquire)) {
            break;
        }

        // Get a connection from the queue
        context.queue_mutex.lock();
        const connection_opt = context.connection_queue.readItem();
        context.queue_mutex.unlock();

        if (connection_opt) |connection| {
            // Handle the connection
            handleConnectionInline(connection) catch |err| {
                logger.err("Error handling connection: {}", .{err});
            };
        }
    }

    logger.debug("Worker thread {d} shutting down", .{context.id});
}

fn handleConnectionInline(connection: std.net.StreamServer.Connection) !void {
    defer connection.stream.close();

    const logger = std.log.scoped(.connection);

    // For extreme load testing, we can skip reading the request and just send a response
    // This simulates a very fast server response and allows testing maximum connection capacity

    // Minimal HTTP response for maximum performance
    const response =
        \\HTTP/1.1 200 OK
        \\Content-Type: text/plain
        \\Content-Length: 2
        \\Connection: close
        \\
        \\OK
    ;

    _ = connection.stream.write(response) catch |err| {
        logger.err("Error writing to connection: {}", .{err});
        return;
    };
}

fn handleConnection(context: *ConnectionContext) !void {
    defer context.allocator.destroy(context);
    defer context.connection.stream.close();

    const logger = std.log.scoped(.connection);
    logger.debug("New connection from {}", .{context.connection.address});

    // Read request
    var buffer: [4096]u8 = undefined;
    const bytes_read = context.connection.stream.read(&buffer) catch |err| {
        logger.err("Error reading from connection: {}", .{err});
        return;
    };

    if (bytes_read == 0) {
        // Client closed connection
        return;
    }

    // Send a simple HTTP response
    const response =
        \\HTTP/1.1 200 OK
        \\Content-Type: text/plain
        \\Content-Length: 13
        \\Connection: close
        \\
        \\Hello, World!
        \\
    ;

    _ = context.connection.stream.write(response) catch |err| {
        logger.err("Error writing to connection: {}", .{err});
        return;
    };
}
