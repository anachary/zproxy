const std = @import("std");
const benchmark = @import("../benchmark.zig");
const crypto = std.crypto;

/// WebSocket opcode
const Opcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
    _,
};

/// WebSocket frame header
const FrameHeader = struct {
    fin: bool,
    rsv1: bool,
    rsv2: bool,
    rsv3: bool,
    opcode: Opcode,
    mask: bool,
    payload_length: u64,
    mask_key: ?[4]u8,

    /// Write a frame header to a buffer
    pub fn write(self: FrameHeader, buffer: []u8) !usize {
        if (buffer.len < 2) {
            return error.BufferTooSmall;
        }

        var bytes_written: usize = 2;

        // First byte
        buffer[0] = 0;
        if (self.fin) buffer[0] |= 0x80;
        if (self.rsv1) buffer[0] |= 0x40;
        if (self.rsv2) buffer[0] |= 0x20;
        if (self.rsv3) buffer[0] |= 0x10;
        buffer[0] |= @intFromEnum(self.opcode) & 0x0F;

        // Second byte
        buffer[1] = 0;
        if (self.mask) buffer[1] |= 0x80;

        // Payload length
        if (self.payload_length <= 125) {
            buffer[1] |= @intCast(self.payload_length & 0x7F);
        } else if (self.payload_length <= 65535) {
            if (buffer.len < 4) {
                return error.BufferTooSmall;
            }

            buffer[1] |= 126;
            buffer[2] = @intCast((self.payload_length >> 8) & 0xFF);
            buffer[3] = @intCast(self.payload_length & 0xFF);
            bytes_written += 2;
        } else {
            if (buffer.len < 10) {
                return error.BufferTooSmall;
            }

            buffer[1] |= 127;
            buffer[2] = @intCast((self.payload_length >> 56) & 0xFF);
            buffer[3] = @intCast((self.payload_length >> 48) & 0xFF);
            buffer[4] = @intCast((self.payload_length >> 40) & 0xFF);
            buffer[5] = @intCast((self.payload_length >> 32) & 0xFF);
            buffer[6] = @intCast((self.payload_length >> 24) & 0xFF);
            buffer[7] = @intCast((self.payload_length >> 16) & 0xFF);
            buffer[8] = @intCast((self.payload_length >> 8) & 0xFF);
            buffer[9] = @intCast(self.payload_length & 0xFF);
            bytes_written += 8;
        }

        // Masking key
        if (self.mask) {
            if (buffer.len < bytes_written + 4) {
                return error.BufferTooSmall;
            }

            if (self.mask_key) |key| {
                buffer[bytes_written] = key[0];
                buffer[bytes_written + 1] = key[1];
                buffer[bytes_written + 2] = key[2];
                buffer[bytes_written + 3] = key[3];
            } else {
                return error.MissingMaskKey;
            }

            bytes_written += 4;
        }

        return bytes_written;
    }

    /// Parse a frame header from a buffer
    pub fn parse(buffer: []const u8) !struct { header: FrameHeader, bytes_read: usize } {
        if (buffer.len < 2) {
            return error.InsufficientData;
        }

        const byte1 = buffer[0];
        const byte2 = buffer[1];

        const fin = (byte1 & 0x80) != 0;
        const rsv1 = (byte1 & 0x40) != 0;
        const rsv2 = (byte1 & 0x20) != 0;
        const rsv3 = (byte1 & 0x10) != 0;
        const opcode = @as(Opcode, @enumFromInt(byte1 & 0x0F));

        const mask = (byte2 & 0x80) != 0;
        var payload_length: u64 = byte2 & 0x7F;

        var bytes_read: usize = 2;

        // Extended payload length
        if (payload_length == 126) {
            if (buffer.len < 4) {
                return error.InsufficientData;
            }

            payload_length = @as(u64, buffer[2]) << 8 | @as(u64, buffer[3]);
            bytes_read += 2;
        } else if (payload_length == 127) {
            if (buffer.len < 10) {
                return error.InsufficientData;
            }

            payload_length = @as(u64, buffer[2]) << 56 | @as(u64, buffer[3]) << 48 | @as(u64, buffer[4]) << 40 | @as(u64, buffer[5]) << 32 | @as(u64, buffer[6]) << 24 | @as(u64, buffer[7]) << 16 | @as(u64, buffer[8]) << 8 | @as(u64, buffer[9]);
            bytes_read += 8;
        }

        // Masking key
        var mask_key: ?[4]u8 = null;
        if (mask) {
            if (buffer.len < bytes_read + 4) {
                return error.InsufficientData;
            }

            mask_key = [4]u8{ buffer[bytes_read], buffer[bytes_read + 1], buffer[bytes_read + 2], buffer[bytes_read + 3] };
            bytes_read += 4;
        }

        return .{
            .header = FrameHeader{
                .fin = fin,
                .rsv1 = rsv1,
                .rsv2 = rsv2,
                .rsv3 = rsv3,
                .opcode = opcode,
                .mask = mask,
                .payload_length = payload_length,
                .mask_key = mask_key,
            },
            .bytes_read = bytes_read,
        };
    }
};

/// WebSocket handshake
fn performWebSocketHandshake(allocator: std.mem.Allocator, socket: std.net.Stream, host: []const u8, path: []const u8) !void {
    // Generate WebSocket key
    var key_bytes: [16]u8 = undefined;
    crypto.random.bytes(&key_bytes);

    var key_base64: [24]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&key_base64, &key_bytes);
    const key = &key_base64;

    // Build handshake request
    var request = std.ArrayList(u8).init(allocator);
    defer request.deinit();

    try request.writer().print("GET {s} HTTP/1.1\r\n", .{path});
    try request.writer().print("Host: {s}\r\n", .{host});
    try request.writer().print("Upgrade: websocket\r\n", .{});
    try request.writer().print("Connection: Upgrade\r\n", .{});
    try request.writer().print("Sec-WebSocket-Key: {s}\r\n", .{key});
    try request.writer().print("Sec-WebSocket-Version: 13\r\n", .{});
    try request.writer().print("\r\n", .{});

    // Send handshake request
    _ = try socket.write(request.items);

    // Read handshake response
    var buffer: [4096]u8 = undefined;
    const bytes_read = try socket.read(&buffer);

    if (bytes_read == 0) {
        return error.EmptyResponse;
    }

    // Check for HTTP 101 response
    if (!std.mem.startsWith(u8, buffer[0..bytes_read], "HTTP/1.1 101")) {
        return error.HandshakeFailed;
    }

    // Check for upgrade header
    if (std.mem.indexOf(u8, buffer[0..bytes_read], "Upgrade: websocket") == null) {
        return error.HandshakeFailed;
    }

    // Check for connection header
    if (std.mem.indexOf(u8, buffer[0..bytes_read], "Connection: Upgrade") == null) {
        return error.HandshakeFailed;
    }

    // Check for accept header
    if (std.mem.indexOf(u8, buffer[0..bytes_read], "Sec-WebSocket-Accept:") == null) {
        return error.HandshakeFailed;
    }

    // Handshake successful
}

/// Mask WebSocket payload
fn maskPayload(payload: []u8, mask_key: [4]u8) void {
    for (payload, 0..) |_, i| {
        payload[i] ^= mask_key[i % 4];
    }
}

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

/// Run a WebSocket benchmark
pub fn runWebSocketBenchmark(allocator: std.mem.Allocator, config: benchmark.BenchmarkConfig) !benchmark.BenchmarkResults {
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

        threads[i] = try std.Thread.spawn(.{}, websocketWorkerThread, .{&contexts[i]});
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

/// WebSocket worker thread function
fn websocketWorkerThread(context: *WorkerContext) !void {
    const allocator = context.allocator;
    const config = context.config;
    const thread_id = context.thread_id;
    const results = context.results;

    // Parse URL
    const url = try std.Uri.parse(config.url);

    // Create connection
    const port = url.port orelse 80;
    const address = try std.net.Address.parseIp(url.host orelse "localhost", port);

    var socket = std.net.tcpConnectToAddress(address) catch |err| {
        try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Connection error: {s}", .{ thread_id, @errorName(err) }));
        return;
    };
    defer socket.close();

    // Set timeouts
    // Note: In newer Zig versions, we would use socket.setReadTimeout and socket.setWriteTimeout
    // For now, we'll skip setting timeouts

    // Perform WebSocket handshake
    performWebSocketHandshake(allocator, socket, url.host orelse "localhost", url.path) catch |err| {
        try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Handshake error: {s}", .{ thread_id, @errorName(err) }));
        return;
    };

    // Create message buffer
    const message_size = if (config.request_size > 0) config.request_size else 32;
    var message = try allocator.alloc(u8, message_size);
    defer allocator.free(message);

    // Fill message with random data
    crypto.random.bytes(message);

    // Create frame buffer
    var frame_buffer = try allocator.alloc(u8, message_size + 14);
    defer allocator.free(frame_buffer);

    // Create response buffer
    var response_buffer: [65536]u8 = undefined;

    // Main loop
    while (!context.stop_flag.load(.SeqCst) and std.time.nanoTimestamp() < context.end_time) {
        // Generate mask key
        var mask_key: [4]u8 = undefined;
        crypto.random.bytes(&mask_key);

        // Create frame header
        const header = FrameHeader{
            .fin = true,
            .rsv1 = false,
            .rsv2 = false,
            .rsv3 = false,
            .opcode = .text,
            .mask = true,
            .payload_length = message.len,
            .mask_key = mask_key,
        };

        // Write frame header
        const header_size = try header.write(frame_buffer);

        // Copy message to frame buffer
        std.mem.copy(u8, frame_buffer[header_size..], message);

        // Mask payload
        maskPayload(frame_buffer[header_size .. header_size + message.len], mask_key);

        // Send frame
        const start_time = std.time.nanoTimestamp();

        _ = socket.write(frame_buffer[0 .. header_size + message.len]) catch |err| {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Write error: {s}", .{ thread_id, @errorName(err) }));
            results.failed_requests.fetchAdd(1, .SeqCst);
            results.requests.fetchAdd(1, .SeqCst);
            continue;
        };

        // Read response
        const bytes_read = socket.read(&response_buffer) catch |err| {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Read error: {s}", .{ thread_id, @errorName(err) }));
            results.failed_requests.fetchAdd(1, .SeqCst);
            results.requests.fetchAdd(1, .SeqCst);
            continue;
        };

        if (bytes_read == 0) {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Empty response", .{thread_id}));
            results.failed_requests.fetchAdd(1, .SeqCst);
            results.requests.fetchAdd(1, .SeqCst);
            continue;
        }

        // Parse frame header
        const frame_result = FrameHeader.parse(response_buffer[0..bytes_read]) catch |err| {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Parse error: {s}", .{ thread_id, @errorName(err) }));
            results.failed_requests.fetchAdd(1, .SeqCst);
            results.requests.fetchAdd(1, .SeqCst);
            continue;
        };

        const frame_header = frame_result.header;
        _ = frame_result.bytes_read;

        // Check if this is a close frame
        if (frame_header.opcode == .close) {
            try results.addError(try std.fmt.allocPrint(allocator, "Thread {d}: Server closed connection", .{thread_id}));
            results.failed_requests.fetchAdd(1, .SeqCst);
            results.requests.fetchAdd(1, .SeqCst);
            break;
        }

        // Update statistics
        results.successful_requests.fetchAdd(1, .SeqCst);
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
