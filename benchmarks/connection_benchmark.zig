const std = @import("std");
const net = std.net;
const time = std.time;
const Atomic = std.atomic.Atomic;
const Thread = std.Thread;

/// Configuration for the connection benchmark
pub const BenchmarkConfig = struct {
    /// Target host to connect to
    host: []const u8,
    /// Target port to connect to
    port: u16,
    /// Number of connections to establish
    connection_count: usize,
    /// Number of concurrent connections to maintain
    concurrency: usize,
    /// Timeout for each connection in milliseconds
    connection_timeout_ms: u64,
    /// Duration of the benchmark in seconds
    duration_seconds: u64,
    /// Whether to keep connections alive after establishing them
    keep_alive: bool,
    /// Whether to send a simple HTTP request after connecting
    send_http_request: bool,
    /// Whether to wait for a response after sending a request
    wait_for_response: bool,
    /// Path to use in HTTP requests
    http_path: []const u8,
};

/// Statistics for the benchmark
pub const BenchmarkStats = struct {
    /// Total number of connection attempts
    total_attempts: Atomic(usize),
    /// Number of successful connections
    successful_connections: Atomic(usize),
    /// Number of failed connections
    failed_connections: Atomic(usize),
    /// Total time spent establishing connections (nanoseconds)
    total_connection_time_ns: Atomic(u64),
    /// Minimum connection time (nanoseconds)
    min_connection_time_ns: Atomic(u64),
    /// Maximum connection time (nanoseconds)
    max_connection_time_ns: Atomic(u64),
    /// Start time of the benchmark
    start_time: i64,
    /// End time of the benchmark
    end_time: i64,
    /// Histogram of connection times (milliseconds)
    connection_time_histogram: std.AutoHashMap(u64, usize),
    /// Mutex for the histogram
    histogram_mutex: Thread.Mutex,
    /// Allocator for the histogram
    allocator: std.mem.Allocator,

    /// Initialize benchmark statistics
    pub fn init(allocator: std.mem.Allocator) BenchmarkStats {
        return BenchmarkStats{
            .total_attempts = Atomic(usize).init(0),
            .successful_connections = Atomic(usize).init(0),
            .failed_connections = Atomic(usize).init(0),
            .total_connection_time_ns = Atomic(u64).init(0),
            .min_connection_time_ns = Atomic(u64).init(std.math.maxInt(u64)),
            .max_connection_time_ns = Atomic(u64).init(0),
            .start_time = 0,
            .end_time = 0,
            .connection_time_histogram = std.AutoHashMap(u64, usize).init(allocator),
            .histogram_mutex = Thread.Mutex{},
            .allocator = allocator,
        };
    }

    /// Record a successful connection
    pub fn recordSuccess(self: *BenchmarkStats, connection_time_ns: u64) void {
        _ = self.total_attempts.fetchAdd(1, .Monotonic);
        _ = self.successful_connections.fetchAdd(1, .Monotonic);
        _ = self.total_connection_time_ns.fetchAdd(connection_time_ns, .Monotonic);

        // Update min connection time
        while (true) {
            const current_min = self.min_connection_time_ns.load(.Acquire);
            if (connection_time_ns >= current_min) break;
            if (self.min_connection_time_ns.compareAndSwap(current_min, connection_time_ns, .AcqRel, .Monotonic) == current_min) break;
        }

        // Update max connection time
        while (true) {
            const current_max = self.max_connection_time_ns.load(.Acquire);
            if (connection_time_ns <= current_max) break;
            if (self.max_connection_time_ns.compareAndSwap(current_max, connection_time_ns, .AcqRel, .Monotonic) == current_max) break;
        }

        // Update histogram (milliseconds)
        const ms = connection_time_ns / time.ns_per_ms;
        self.histogram_mutex.lock();
        defer self.histogram_mutex.unlock();

        var entry = self.connection_time_histogram.getOrPut(ms) catch return;
        if (!entry.found_existing) {
            entry.value_ptr.* = 0;
        }
        entry.value_ptr.* += 1;
    }

    /// Record a failed connection
    pub fn recordFailure(self: *BenchmarkStats) void {
        _ = self.total_attempts.fetchAdd(1, .Monotonic);
        _ = self.failed_connections.fetchAdd(1, .Monotonic);
    }

    /// Get the average connection time in milliseconds
    pub fn getAverageConnectionTimeMs(self: *const BenchmarkStats) f64 {
        const successful = self.successful_connections.load(.Acquire);
        if (successful == 0) return 0;

        const total_ns = self.total_connection_time_ns.load(.Acquire);
        return @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(successful)) / @as(f64, @floatFromInt(time.ns_per_ms));
    }

    /// Get the connection rate (connections per second)
    pub fn getConnectionRate(self: *const BenchmarkStats) f64 {
        const duration_ns = self.end_time - self.start_time;
        if (duration_ns <= 0) return 0;

        const successful = self.successful_connections.load(.Acquire);
        return @as(f64, @floatFromInt(successful)) / (@as(f64, @floatFromInt(duration_ns)) / @as(f64, @floatFromInt(time.ns_per_s)));
    }

    /// Get the success rate (percentage)
    pub fn getSuccessRate(self: *const BenchmarkStats) f64 {
        const total = self.total_attempts.load(.Acquire);
        if (total == 0) return 0;

        const successful = self.successful_connections.load(.Acquire);
        return @as(f64, @floatFromInt(successful)) / @as(f64, @floatFromInt(total)) * 100.0;
    }

    /// Print benchmark results
    pub fn printResults(self: *const BenchmarkStats) void {
        const stdout = std.io.getStdOut().writer();

        // Calculate duration
        const duration_ns = self.end_time - self.start_time;
        const duration_s = @as(f64, @floatFromInt(duration_ns)) / @as(f64, @floatFromInt(time.ns_per_s));

        // Get statistics
        const total = self.total_attempts.load(.Acquire);
        const successful = self.successful_connections.load(.Acquire);
        const failed = self.failed_connections.load(.Acquire);
        const avg_time_ms = self.getAverageConnectionTimeMs();
        const min_time_ms = @as(f64, @floatFromInt(self.min_connection_time_ns.load(.Acquire))) / @as(f64, @floatFromInt(time.ns_per_ms));
        const max_time_ms = @as(f64, @floatFromInt(self.max_connection_time_ns.load(.Acquire))) / @as(f64, @floatFromInt(time.ns_per_ms));
        const conn_rate = self.getConnectionRate();
        const success_rate = self.getSuccessRate();

        // Print summary
        stdout.print("\n=== Connection Benchmark Results ===\n", .{}) catch {};
        stdout.print("Duration: {d:.2} seconds\n", .{duration_s}) catch {};
        stdout.print("Total connection attempts: {d}\n", .{total}) catch {};
        stdout.print("Successful connections: {d}\n", .{successful}) catch {};
        stdout.print("Failed connections: {d}\n", .{failed}) catch {};
        stdout.print("Success rate: {d:.2}%\n", .{success_rate}) catch {};
        stdout.print("Connection rate: {d:.2} connections/second\n", .{conn_rate}) catch {};
        stdout.print("Average connection time: {d:.2} ms\n", .{avg_time_ms}) catch {};
        stdout.print("Min connection time: {d:.2} ms\n", .{min_time_ms}) catch {};
        stdout.print("Max connection time: {d:.2} ms\n", .{max_time_ms}) catch {};

        // Print histogram
        stdout.print("\nConnection Time Histogram (ms):\n", .{}) catch {};

        // Get sorted keys
        var keys = std.ArrayList(u64).init(self.allocator);
        defer keys.deinit();

        {
            var it = self.connection_time_histogram.keyIterator();
            while (it.next()) |key| {
                keys.append(key.*) catch continue;
            }
        }

        std.sort.sort(u64, keys.items, {}, comptime std.sort.asc(u64));

        for (keys.items) |ms| {
            if (self.connection_time_histogram.get(ms)) |count| {
                const percentage = @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(successful)) * 100.0;
                stdout.print("{d} ms: {d} ({d:.2}%)\n", .{ ms, count, percentage }) catch {};
            }
        }

        stdout.print("\n", .{}) catch {};
    }
};

/// Worker context for benchmark threads
const WorkerContext = struct {
    /// Thread ID
    id: usize,
    /// Benchmark configuration
    config: *const BenchmarkConfig,
    /// Benchmark statistics
    stats: *BenchmarkStats,
    /// Semaphore for limiting concurrency
    semaphore: *Thread.Semaphore,
    /// Atomic flag indicating whether the benchmark is running
    running: *Atomic(bool),
};

/// Run a connection benchmark
pub fn runBenchmark(allocator: std.mem.Allocator, config: BenchmarkConfig) !BenchmarkStats {
    var stats = BenchmarkStats.init(allocator);

    // Parse the target address
    const address = try net.Address.parseIp(config.host, config.port);
    _ = address;

    // Create a semaphore to limit concurrency
    var semaphore = Thread.Semaphore{};
    semaphore.setValue(config.concurrency);

    // Create an atomic flag to signal threads to stop
    var running = Atomic(bool).init(true);

    // Create worker threads
    const thread_count = @min(config.concurrency, 32); // Limit to 32 threads
    var threads = try allocator.alloc(Thread, thread_count);
    defer allocator.free(threads);

    var contexts = try allocator.alloc(WorkerContext, thread_count);
    defer allocator.free(contexts);

    // Record start time
    stats.start_time = time.nanoTimestamp();

    // Start worker threads
    for (0..thread_count) |i| {
        contexts[i] = WorkerContext{
            .id = i,
            .config = &config,
            .stats = &stats,
            .semaphore = &semaphore,
            .running = &running,
        };

        threads[i] = try Thread.spawn(.{}, workerThread, .{&contexts[i]});
    }

    // Wait for the specified duration
    std.time.sleep(config.duration_seconds * time.ns_per_s);

    // Signal threads to stop
    running.store(false, .Release);

    // Wait for all threads to finish
    for (threads) |thread| {
        thread.join();
    }

    // Record end time
    stats.end_time = time.nanoTimestamp();

    return stats;
}

/// Worker thread function
fn workerThread(context: *WorkerContext) !void {
    const config = context.config;
    const stats = context.stats;
    const semaphore = context.semaphore;
    const running = context.running;

    // Prepare HTTP request if needed
    var http_request: []const u8 = "";
    if (config.send_http_request) {
        http_request = try std.fmt.allocPrint(
            stats.allocator,
            "GET {s} HTTP/1.1\r\nHost: {s}:{d}\r\nConnection: {s}\r\n\r\n",
            .{
                config.http_path,
                config.host,
                config.port,
                if (config.keep_alive) "keep-alive" else "close",
            },
        );
        defer stats.allocator.free(http_request);
    }

    // Parse the target address once for all connections
    var address = try net.Address.parseIp(config.host, config.port);

    // Connection loop
    while (running.load(.Acquire)) {
        // Wait for a semaphore slot
        semaphore.wait();

        // Check if we should stop
        if (!running.load(.Acquire)) {
            semaphore.post();
            break;
        }

        // Establish a connection
        const start_time = time.nanoTimestamp();
        const stream = net.tcpConnectToAddress(address) catch {
            stats.recordFailure();
            semaphore.post();
            continue;
        };
        defer {
            if (!config.keep_alive) {
                stream.close();
            }
        }

        // Set timeout if specified
        if (config.connection_timeout_ms > 0) {
            stream.setReadTimeout(config.connection_timeout_ms * time.ns_per_ms) catch {};
            stream.setWriteTimeout(config.connection_timeout_ms * time.ns_per_ms) catch {};
        }

        // Send HTTP request if needed
        if (config.send_http_request) {
            _ = stream.write(http_request) catch {
                stats.recordFailure();
                stream.close();
                semaphore.post();
                continue;
            };

            // Wait for response if needed
            if (config.wait_for_response) {
                var buffer: [4096]u8 = undefined;
                _ = stream.read(&buffer) catch {
                    stats.recordFailure();
                    stream.close();
                    semaphore.post();
                    continue;
                };
            }
        }

        // Record connection time
        const end_time = time.nanoTimestamp();
        const connection_time = @as(u64, @intCast(end_time - start_time));
        stats.recordSuccess(connection_time);

        // Close connection if not keeping alive
        if (!config.keep_alive) {
            stream.close();
        }

        // Release semaphore slot
        semaphore.post();
    }
}

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Default configuration
    var config = BenchmarkConfig{
        .host = "127.0.0.1",
        .port = 8080,
        .connection_count = 100000,
        .concurrency = 1000,
        .connection_timeout_ms = 5000,
        .duration_seconds = 30,
        .keep_alive = false,
        .send_http_request = true,
        .wait_for_response = true,
        .http_path = "/",
    };

    // Parse arguments
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--host") and i + 1 < args.len) {
            config.host = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--port") and i + 1 < args.len) {
            config.port = try std.fmt.parseInt(u16, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--connections") and i + 1 < args.len) {
            config.connection_count = try std.fmt.parseInt(usize, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--concurrency") and i + 1 < args.len) {
            config.concurrency = try std.fmt.parseInt(usize, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--timeout") and i + 1 < args.len) {
            config.connection_timeout_ms = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--duration") and i + 1 < args.len) {
            config.duration_seconds = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, arg, "--keep-alive")) {
            config.keep_alive = true;
        } else if (std.mem.eql(u8, arg, "--no-http")) {
            config.send_http_request = false;
            config.wait_for_response = false;
        } else if (std.mem.eql(u8, arg, "--no-wait")) {
            config.wait_for_response = false;
        } else if (std.mem.eql(u8, arg, "--path") and i + 1 < args.len) {
            config.http_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return;
        }
    }

    // Print benchmark configuration
    const stdout = std.io.getStdOut().writer();
    try stdout.print("=== Connection Benchmark Configuration ===\n", .{});
    try stdout.print("Target: {s}:{d}\n", .{ config.host, config.port });
    try stdout.print("Concurrency: {d}\n", .{config.concurrency});
    try stdout.print("Duration: {d} seconds\n", .{config.duration_seconds});
    try stdout.print("Connection timeout: {d} ms\n", .{config.connection_timeout_ms});
    try stdout.print("Keep alive: {}\n", .{config.keep_alive});
    try stdout.print("Send HTTP request: {}\n", .{config.send_http_request});
    try stdout.print("Wait for response: {}\n", .{config.wait_for_response});
    if (config.send_http_request) {
        try stdout.print("HTTP path: {s}\n", .{config.http_path});
    }
    try stdout.print("\nStarting benchmark...\n", .{});

    // Run the benchmark
    var stats = try runBenchmark(allocator, config);

    // Print results
    stats.printResults();
}

/// Print usage information
fn printUsage() void {
    const stdout = std.io.getStdOut().writer();
    stdout.print(
        \\Usage: connection_benchmark [options]
        \\
        \\Options:
        \\  --host HOST             Target host (default: 127.0.0.1)
        \\  --port PORT             Target port (default: 8080)
        \\  --connections COUNT     Number of connections to establish (default: 100000)
        \\  --concurrency COUNT     Number of concurrent connections (default: 1000)
        \\  --timeout MS            Connection timeout in milliseconds (default: 5000)
        \\  --duration SECONDS      Benchmark duration in seconds (default: 30)
        \\  --keep-alive            Keep connections alive after establishing them
        \\  --no-http               Don't send HTTP requests
        \\  --no-wait               Don't wait for responses
        \\  --path PATH             HTTP request path (default: /)
        \\  --help                  Show this help message
        \\
    , .{}) catch {};
}
