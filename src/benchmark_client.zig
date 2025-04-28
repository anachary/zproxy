const std = @import("std");

pub fn main() !void {
    // Parse command line arguments
    var args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 5) {
        std.debug.print("Usage: {s} <url> <connections> <duration_seconds> <concurrency>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const url = args[1];
    const connections = try std.fmt.parseInt(u32, args[2], 10);
    const duration_seconds = try std.fmt.parseInt(u32, args[3], 10);
    const concurrency = try std.fmt.parseInt(u32, args[4], 10);

    std.debug.print("Benchmarking {s}\n", .{url});
    std.debug.print("Connections: {d}, Duration: {d}s, Concurrency: {d}\n", .{
        connections, duration_seconds, concurrency,
    });

    // Parse URL
    var uri = try std.Uri.parse(url);
    const host = uri.host orelse return error.MissingHost;
    const port = uri.port orelse 80;

    // Create a general purpose allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a thread pool
    var thread_pool: std.ArrayList(std.Thread) = std.ArrayList(std.Thread).init(allocator);
    defer thread_pool.deinit();

    // Create shared state
    var state = BenchmarkState{
        .allocator = allocator,
        .host = host,
        .port = port,
        .path = uri.path,
        .connections_per_thread = connections / concurrency,
        .duration_ns = @as(u64, duration_seconds) * @as(u64, @intCast(std.time.ns_per_s)),
        .successful_requests = std.atomic.Atomic(u64).init(0),
        .failed_requests = std.atomic.Atomic(u64).init(0),
        .total_latency_ns = std.atomic.Atomic(u64).init(0),
        .min_latency_ns = std.atomic.Atomic(u64).init(std.math.maxInt(u64)),
        .max_latency_ns = std.atomic.Atomic(u64).init(0),
    };

    // Start the benchmark
    const start_time = std.time.nanoTimestamp();

    // Create worker threads
    try thread_pool.ensureTotalCapacity(concurrency);
    for (0..concurrency) |i| {
        const thread = try std.Thread.spawn(.{}, workerThread, .{ &state, i });
        try thread_pool.append(thread);
    }

    // Wait for all threads to complete
    for (thread_pool.items) |thread| {
        thread.join();
    }

    // Calculate results
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_seconds_f = @as(f64, @floatFromInt(duration_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));

    const successful_requests = state.successful_requests.load(.SeqCst);
    const failed_requests = state.failed_requests.load(.SeqCst);
    const total_requests = successful_requests + failed_requests;
    const requests_per_second = @as(f64, @floatFromInt(total_requests)) / duration_seconds_f;

    const total_latency_ns = state.total_latency_ns.load(.SeqCst);
    const avg_latency_ms = if (total_requests > 0)
        @as(f64, @floatFromInt(total_latency_ns)) / @as(f64, @floatFromInt(total_requests)) / std.time.ns_per_ms
    else
        0;

    const min_latency_ms = @as(f64, @floatFromInt(state.min_latency_ns.load(.SeqCst))) / std.time.ns_per_ms;
    const max_latency_ms = @as(f64, @floatFromInt(state.max_latency_ns.load(.SeqCst))) / std.time.ns_per_ms;

    // Print results
    std.debug.print("\nBenchmark Results:\n", .{});
    std.debug.print("  Duration: {d:.2} seconds\n", .{duration_seconds_f});
    std.debug.print("  Requests: {d}\n", .{total_requests});
    std.debug.print("  Successful: {d} ({d:.2}%)\n", .{
        successful_requests,
        if (total_requests > 0) @as(f64, @floatFromInt(successful_requests)) / @as(f64, @floatFromInt(total_requests)) * 100 else 0,
    });
    std.debug.print("  Failed: {d} ({d:.2}%)\n", .{
        failed_requests,
        if (total_requests > 0) @as(f64, @floatFromInt(failed_requests)) / @as(f64, @floatFromInt(total_requests)) * 100 else 0,
    });
    std.debug.print("  Requests/second: {d:.2}\n", .{requests_per_second});
    std.debug.print("  Latency:\n", .{});
    std.debug.print("    Average: {d:.2} ms\n", .{avg_latency_ms});
    std.debug.print("    Minimum: {d:.2} ms\n", .{min_latency_ms});
    std.debug.print("    Maximum: {d:.2} ms\n", .{max_latency_ms});
}

const BenchmarkState = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    path: []const u8,
    connections_per_thread: u32,
    duration_ns: u64,
    successful_requests: std.atomic.Atomic(u64),
    failed_requests: std.atomic.Atomic(u64),
    total_latency_ns: std.atomic.Atomic(u64),
    min_latency_ns: std.atomic.Atomic(u64),
    max_latency_ns: std.atomic.Atomic(u64),
};

fn workerThread(state: *BenchmarkState, thread_id: usize) !void {
    const start_time = std.time.nanoTimestamp();
    const end_time = start_time + @as(i64, @intCast(state.duration_ns));

    // Create a buffer for the request
    var request_buffer = try state.allocator.alloc(u8, 1024);
    defer state.allocator.free(request_buffer);

    // Format the HTTP request
    const request_slice = try std.fmt.bufPrint(request_buffer, "GET {s} HTTP/1.1\r\nHost: {s}\r\nConnection: keep-alive\r\n\r\n", .{
        state.path,
        state.host,
    });

    // Create a buffer for the response
    var response_buffer = try state.allocator.alloc(u8, 4096);
    defer state.allocator.free(response_buffer);

    // Resolve the address
    const address = try std.net.Address.parseIp(state.host, state.port);

    // Main benchmark loop
    while (std.time.nanoTimestamp() < end_time) {
        // Connect to the server
        const request_start = std.time.nanoTimestamp();
        const socket = std.net.tcpConnectToAddress(address) catch |err| {
            std.debug.print("Thread {d}: Connection error: {s}\n", .{ thread_id, @errorName(err) });
            _ = state.failed_requests.fetchAdd(1, .SeqCst);
            continue;
        };
        defer socket.close();

        // Send the request
        _ = try socket.write(request_slice);

        // Read the response
        const bytes_read = socket.read(response_buffer) catch |err| {
            std.debug.print("Thread {d}: Read error: {s}\n", .{ thread_id, @errorName(err) });
            _ = state.failed_requests.fetchAdd(1, .SeqCst);
            continue;
        };

        if (bytes_read == 0) {
            std.debug.print("Thread {d}: Empty response\n", .{thread_id});
            _ = state.failed_requests.fetchAdd(1, .SeqCst);
            continue;
        }

        // Calculate latency
        const request_end = std.time.nanoTimestamp();
        const latency_ns = @as(u64, @intCast(request_end - request_start));

        // Update statistics
        _ = state.successful_requests.fetchAdd(1, .SeqCst);
        _ = state.total_latency_ns.fetchAdd(latency_ns, .SeqCst);

        // Update min latency
        while (true) {
            const current_min = state.min_latency_ns.load(.SeqCst);
            if (latency_ns >= current_min) break;
            if (state.min_latency_ns.compareAndSwap(current_min, latency_ns, .SeqCst, .SeqCst) == null) break;
        }

        // Update max latency
        while (true) {
            const current_max = state.max_latency_ns.load(.SeqCst);
            if (latency_ns <= current_max) break;
            if (state.max_latency_ns.compareAndSwap(current_max, latency_ns, .SeqCst, .SeqCst) == null) break;
        }
    }
}
