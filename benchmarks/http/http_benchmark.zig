const std = @import("std");
const benchmark = @import("../benchmark.zig");

/// HTTP request
const HttpRequest = struct {
    method: []const u8,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    /// Initialize a new HTTP request
    pub fn init(allocator: std.mem.Allocator) !HttpRequest {
        return HttpRequest{
            .method = "GET",
            .path = "/",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
        };
    }

    /// Clean up HTTP request resources
    pub fn deinit(self: *HttpRequest) void {
        self.headers.deinit();
    }

    /// Set a header
    pub fn setHeader(self: *HttpRequest, name: []const u8, value: []const u8) !void {
        const name_copy = try self.headers.allocator.dupe(u8, name);
        errdefer self.headers.allocator.free(name_copy);

        const value_copy = try self.headers.allocator.dupe(u8, value);
        errdefer self.headers.allocator.free(value_copy);

        // Remove existing header if any
        if (self.headers.getKey(name)) |existing_name| {
            const existing_value = self.headers.get(existing_name).?;
            self.headers.allocator.free(existing_name);
            self.headers.allocator.free(existing_value);
            _ = self.headers.remove(existing_name);
        }

        try self.headers.put(name_copy, value_copy);
    }

    /// Build the HTTP request
    pub fn build(self: *const HttpRequest, allocator: std.mem.Allocator) ![]const u8 {
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        // Request line
        try buffer.writer().print("{s} {s} HTTP/1.1\r\n", .{ self.method, self.path });

        // Headers
        var headers_it = self.headers.iterator();
        while (headers_it.next()) |entry| {
            try buffer.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // Empty line
        try buffer.writer().writeAll("\r\n");

        // Body
        if (self.body.len > 0) {
            try buffer.writer().writeAll(self.body);
        }

        return buffer.toOwnedSlice();
    }
};

/// HTTP response
const HttpResponse = struct {
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,

    /// Initialize a new HTTP response
    pub fn init(allocator: std.mem.Allocator) !HttpResponse {
        return HttpResponse{
            .status_code = 0,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
        };
    }

    /// Clean up HTTP response resources
    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
    }

    /// Parse an HTTP response
    pub fn parse(allocator: std.mem.Allocator, buffer: []const u8) !HttpResponse {
        var response = try HttpResponse.init(allocator);
        errdefer response.deinit();

        // Find the end of the status line
        const status_line_end = std.mem.indexOf(u8, buffer, "\r\n") orelse return error.InvalidResponse;
        const status_line = buffer[0..status_line_end];

        // Parse status line
        var status_line_it = std.mem.split(u8, status_line, " ");
        const version = status_line_it.next() orelse return error.InvalidResponse;
        const status_code_str = status_line_it.next() orelse return error.InvalidResponse;

        // Check HTTP version
        if (!std.mem.eql(u8, version, "HTTP/1.1") and !std.mem.eql(u8, version, "HTTP/1.0")) {
            return error.UnsupportedHttpVersion;
        }

        // Parse status code
        response.status_code = try std.fmt.parseInt(u16, status_code_str, 10);

        // Find the end of the headers
        const headers_end = std.mem.indexOf(u8, buffer[status_line_end + 2 ..], "\r\n\r\n") orelse return error.InvalidResponse;
        const headers_section = buffer[status_line_end + 2 .. status_line_end + 2 + headers_end];

        // Parse headers
        var header_start: usize = 0;
        while (header_start < headers_section.len) {
            const header_end = std.mem.indexOf(u8, headers_section[header_start..], "\r\n") orelse break;
            const header_line = headers_section[header_start .. header_start + header_end];

            const colon_pos = std.mem.indexOf(u8, header_line, ":") orelse return error.InvalidHeader;
            const header_name = std.mem.trim(u8, header_line[0..colon_pos], " ");
            const header_value = std.mem.trim(u8, header_line[colon_pos + 1 ..], " ");

            const name_copy = try allocator.dupe(u8, header_name);
            errdefer allocator.free(name_copy);

            const value_copy = try allocator.dupe(u8, header_value);
            errdefer allocator.free(value_copy);

            try response.headers.put(name_copy, value_copy);

            header_start += header_end + 2;
        }

        // Parse body
        const body_start = status_line_end + 2 + headers_end + 4;
        if (body_start < buffer.len) {
            response.body = try allocator.dupe(u8, buffer[body_start..]);
        }

        return response;
    }
};

/// Worker thread context
const WorkerContext = struct {
    allocator: std.mem.Allocator,
    config: benchmark.BenchmarkConfig,
    thread_id: usize,
    start_time: i64,
    end_time: i64,
    stop_flag: *std.atomic.Atomic(bool),
    results: *ThreadResults,
    latencies: *std.ArrayList(u64),
    latencies_mutex: *std.Thread.Mutex,
};

/// Thread results
const ThreadResults = struct {
    requests: std.atomic.Atomic(u64),
    successful_requests: std.atomic.Atomic(u64),
    failed_requests: std.atomic.Atomic(u64),
    bytes_received: std.atomic.Atomic(u64),
    total_latency_ns: std.atomic.Atomic(u64),
    min_latency_ns: std.atomic.Atomic(u64),
    max_latency_ns: std.atomic.Atomic(u64),
    errors: std.ArrayList([]const u8),
    errors_mutex: std.Thread.Mutex,

    /// Initialize thread results
    pub fn init(allocator: std.mem.Allocator) ThreadResults {
        return ThreadResults{
            .requests = std.atomic.Atomic(u64).init(0),
            .successful_requests = std.atomic.Atomic(u64).init(0),
            .failed_requests = std.atomic.Atomic(u64).init(0),
            .bytes_received = std.atomic.Atomic(u64).init(0),
            .total_latency_ns = std.atomic.Atomic(u64).init(0),
            .min_latency_ns = std.atomic.Atomic(u64).init(std.math.maxInt(u64)),
            .max_latency_ns = std.atomic.Atomic(u64).init(0),
            .errors = std.ArrayList([]const u8).init(allocator),
            .errors_mutex = std.Thread.Mutex{},
        };
    }

    /// Clean up thread results
    pub fn deinit(self: *ThreadResults) void {
        for (self.errors.items) |error_msg| {
            self.errors.allocator.free(error_msg);
        }
        self.errors.deinit();
    }

    /// Add an error message
    pub fn addError(self: *ThreadResults, error_msg: []const u8) !void {
        self.errors_mutex.lock();
        defer self.errors_mutex.unlock();

        const msg_copy = try self.errors.allocator.dupe(u8, error_msg);
        try self.errors.append(msg_copy);
    }
};

/// Run an HTTP benchmark
pub fn runHttpBenchmark(allocator: std.mem.Allocator, config: benchmark.BenchmarkConfig) !benchmark.BenchmarkResults {
    // Parse URL
    _ = try std.Uri.parse(config.url);

    // Create thread results
    var thread_results = ThreadResults.init(allocator);
    defer thread_results.deinit();

    // Create latencies array
    var latencies = std.ArrayList(u64).init(allocator);
    defer latencies.deinit();

    // Create latencies mutex
    var latencies_mutex = std.Thread.Mutex{};

    // Create stop flag
    var stop_flag = std.atomic.Atomic(bool).init(false);

    // Create worker threads
    var threads = try allocator.alloc(std.Thread, config.concurrency);
    defer allocator.free(threads);

    var contexts = try allocator.alloc(WorkerContext, config.concurrency);
    defer allocator.free(contexts);

    // Start time
    const start_time = std.time.nanoTimestamp();

    // Create and start worker threads
    for (0..config.concurrency) |i| {
        contexts[i] = WorkerContext{
            .allocator = allocator,
            .config = config,
            .thread_id = i,
            .start_time = @intCast(start_time),
            .end_time = @intCast(start_time + @as(i64, @intCast(config.duration_seconds)) * @as(i64, @intCast(std.time.ns_per_s))),
            .stop_flag = &stop_flag,
            .results = &thread_results,
            .latencies = &latencies,
            .latencies_mutex = &latencies_mutex,
        };

        threads[i] = try std.Thread.spawn(.{}, workerThread, .{&contexts[i]});
    }

    // Wait for duration
    std.time.sleep(config.duration_seconds * std.time.ns_per_s);

    // Set stop flag
    stop_flag.store(true, .SeqCst);

    // Wait for all threads to finish
    for (threads) |thread| {
        thread.join();
    }

    // End time
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));

    // Calculate statistics
    const duration_seconds = @as(f64, @floatFromInt(duration_ns)) / @as(f64, @floatFromInt(std.time.ns_per_s));
    const requests = thread_results.requests.load(.SeqCst);
    const successful_requests = thread_results.successful_requests.load(.SeqCst);
    const failed_requests = thread_results.failed_requests.load(.SeqCst);
    const bytes_received = thread_results.bytes_received.load(.SeqCst);
    const total_latency_ns = thread_results.total_latency_ns.load(.SeqCst);
    const min_latency_ns = thread_results.min_latency_ns.load(.SeqCst);
    const max_latency_ns = thread_results.max_latency_ns.load(.SeqCst);

    const requests_per_second = @as(f64, @floatFromInt(requests)) / duration_seconds;
    const avg_latency_ms = if (requests > 0) @as(f64, @floatFromInt(total_latency_ns)) / @as(f64, @floatFromInt(requests)) / std.time.ns_per_ms else 0;
    const min_latency_ms = @as(f64, @floatFromInt(min_latency_ns)) / std.time.ns_per_ms;
    const max_latency_ms = @as(f64, @floatFromInt(max_latency_ns)) / std.time.ns_per_ms;
    const transfer_rate_bps = @as(f64, @floatFromInt(bytes_received)) / duration_seconds;

    // Calculate percentiles
    var p50_latency_ms: f64 = 0;
    var p90_latency_ms: f64 = 0;
    var p99_latency_ms: f64 = 0;

    if (latencies.items.len > 0) {
        // Sort latencies
        std.sort.heap(u64, latencies.items, {}, comptime std.sort.asc(u64));

        // Calculate percentiles
        const p50_index = @divFloor(latencies.items.len * 50, 100);
        const p90_index = @divFloor(latencies.items.len * 90, 100);
        const p99_index = @divFloor(latencies.items.len * 99, 100);

        p50_latency_ms = @as(f64, @floatFromInt(latencies.items[p50_index])) / std.time.ns_per_ms;
        p90_latency_ms = @as(f64, @floatFromInt(latencies.items[p90_index])) / std.time.ns_per_ms;
        p99_latency_ms = @as(f64, @floatFromInt(latencies.items[p99_index])) / std.time.ns_per_ms;
    }

    // Create benchmark results
    var results = benchmark.BenchmarkResults.init(allocator);

    results.duration_seconds = duration_seconds;
    results.requests = requests;
    results.successful_requests = successful_requests;
    results.failed_requests = failed_requests;
    results.requests_per_second = requests_per_second;
    results.avg_latency_ms = avg_latency_ms;
    results.min_latency_ms = min_latency_ms;
    results.max_latency_ms = max_latency_ms;
    results.p50_latency_ms = p50_latency_ms;
    results.p90_latency_ms = p90_latency_ms;
    results.p99_latency_ms = p99_latency_ms;
    results.bytes_received = bytes_received;
    results.transfer_rate_bps = transfer_rate_bps;

    // Copy errors
    for (thread_results.errors.items) |error_msg| {
        try results.addError(error_msg);
    }

    return results;
}

/// Worker thread function
fn workerThread(context: *WorkerContext) !void {
    const allocator = context.allocator;
    const config = context.config;
    const thread_id = context.thread_id;
    const results = context.results;

    // Parse URL
    const url = try std.Uri.parse(config.url);

    // Create HTTP request
    var request = try HttpRequest.init(allocator);
    defer request.deinit();

    // Set headers
    try request.setHeader("Host", url.host orelse "localhost");
    try request.setHeader("User-Agent", "ZProxy-Benchmark");
    try request.setHeader("Accept", "*/*");

    if (config.keep_alive) {
        try request.setHeader("Connection", "keep-alive");
    } else {
        try request.setHeader("Connection", "close");
    }

    // Set path
    request.path = url.path;
    if (request.path.len == 0) {
        request.path = "/";
    }

    // Build request
    const request_data = try request.build(allocator);
    defer allocator.free(request_data);

    // Create buffer for response
    var buffer: [65536]u8 = undefined;

    // Create connection
    const port = url.port orelse 80;
    const address = try std.net.Address.parseIp(url.host orelse "localhost", port);

    // Main loop
    while (!context.stop_flag.load(.SeqCst) and std.time.nanoTimestamp() < context.end_time) {
        // Connect to server
        const start_time = std.time.nanoTimestamp();

        var socket = std.net.tcpConnectToAddress(address) catch |err| {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Connection error: {s}", .{ thread_id, @errorName(err) }));
            _ = results.failed_requests.fetchAdd(1, .SeqCst);
            _ = results.requests.fetchAdd(1, .SeqCst);
            continue;
        };
        defer socket.close();

        // Set timeouts
        // Note: In newer Zig versions, we would use socket.setReadTimeout and socket.setWriteTimeout
        // For now, we'll skip setting timeouts

        // Send request
        _ = try socket.write(request_data);

        // Read response
        const bytes_read = socket.read(&buffer) catch |err| {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Read error: {s}", .{ thread_id, @errorName(err) }));
            _ = results.failed_requests.fetchAdd(1, .SeqCst);
            _ = results.requests.fetchAdd(1, .SeqCst);
            continue;
        };

        if (bytes_read == 0) {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Empty response", .{thread_id}));
            _ = results.failed_requests.fetchAdd(1, .SeqCst);
            _ = results.requests.fetchAdd(1, .SeqCst);
            continue;
        }

        // Parse response
        var response = HttpResponse.parse(allocator, buffer[0..bytes_read]) catch |err| {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Parse error: {s}", .{ thread_id, @errorName(err) }));
            _ = results.failed_requests.fetchAdd(1, .SeqCst);
            _ = results.requests.fetchAdd(1, .SeqCst);
            continue;
        };
        defer response.deinit();

        // Check status code
        if (response.status_code < 200 or response.status_code >= 400) {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: HTTP error: {d}", .{ thread_id, response.status_code }));
            _ = results.failed_requests.fetchAdd(1, .SeqCst);
        } else {
            _ = results.successful_requests.fetchAdd(1, .SeqCst);
        }

        // Update statistics
        results.requests.fetchAdd(1, .SeqCst);
        results.bytes_received.fetchAdd(bytes_read, .SeqCst);

        // Calculate latency
        const end_time = std.time.nanoTimestamp();
        const latency_ns = @as(u64, @intCast(end_time - start_time));

        results.total_latency_ns.fetchAdd(latency_ns, .SeqCst);

        // Update min/max latency
        while (true) {
            const current_min = results.min_latency_ns.load(.SeqCst);
            if (latency_ns >= current_min) break;
            if (results.min_latency_ns.compareAndSwap(current_min, latency_ns, .SeqCst, .SeqCst) == null) break;
        }

        while (true) {
            const current_max = results.max_latency_ns.load(.SeqCst);
            if (latency_ns <= current_max) break;
            if (results.max_latency_ns.compareAndSwap(current_max, latency_ns, .SeqCst, .SeqCst) == null) break;
        }

        // Add latency to list for percentile calculation
        context.latencies_mutex.lock();
        context.latencies.append(latency_ns) catch {};
        context.latencies_mutex.unlock();

        // Sleep if request rate is limited
        if (config.request_rate > 0) {
            const sleep_time = std.time.ns_per_s / config.request_rate;
            std.time.sleep(sleep_time);
        }
    }
}
