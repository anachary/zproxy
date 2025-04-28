const std = @import("std");
const http = @import("http/http_benchmark.zig");
const websocket = @import("websocket/websocket_benchmark.zig");

/// Benchmark configuration
pub const BenchmarkConfig = struct {
    /// Target URL to benchmark
    url: []const u8,
    /// Number of connections to make
    connections: u32,
    /// Duration of the benchmark in seconds
    duration_seconds: u32,
    /// Number of concurrent connections
    concurrency: u32,
    /// Whether to use HTTP keep-alive
    keep_alive: bool,
    /// Protocol to benchmark
    protocol: Protocol,
    /// Request size in bytes (for WebSocket)
    request_size: u32,
    /// Response size in bytes (for WebSocket)
    response_size: u32,
    /// Request rate per second (0 for unlimited)
    request_rate: u32,
    /// Output file for results (null for stdout)
    output_file: ?[]const u8,
    /// Verbose output
    verbose: bool,
};

/// Protocol to benchmark
pub const Protocol = enum {
    http1,
    http2,
    websocket,
};

/// Benchmark results
pub const BenchmarkResults = struct {
    /// Duration of the benchmark in seconds
    duration_seconds: f64,
    /// Total number of requests
    requests: u64,
    /// Total number of successful requests
    successful_requests: u64,
    /// Total number of failed requests
    failed_requests: u64,
    /// Requests per second
    requests_per_second: f64,
    /// Average latency in milliseconds
    avg_latency_ms: f64,
    /// Minimum latency in milliseconds
    min_latency_ms: f64,
    /// Maximum latency in milliseconds
    max_latency_ms: f64,
    /// 50th percentile latency in milliseconds
    p50_latency_ms: f64,
    /// 90th percentile latency in milliseconds
    p90_latency_ms: f64,
    /// 99th percentile latency in milliseconds
    p99_latency_ms: f64,
    /// Total bytes received
    bytes_received: u64,
    /// Transfer rate in bytes per second
    transfer_rate_bps: f64,
    /// Error messages
    errors: std.ArrayList([]const u8),
    
    /// Initialize benchmark results
    pub fn init(allocator: std.mem.Allocator) BenchmarkResults {
        return BenchmarkResults{
            .duration_seconds = 0,
            .requests = 0,
            .successful_requests = 0,
            .failed_requests = 0,
            .requests_per_second = 0,
            .avg_latency_ms = 0,
            .min_latency_ms = 0,
            .max_latency_ms = 0,
            .p50_latency_ms = 0,
            .p90_latency_ms = 0,
            .p99_latency_ms = 0,
            .bytes_received = 0,
            .transfer_rate_bps = 0,
            .errors = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    /// Clean up benchmark results
    pub fn deinit(self: *BenchmarkResults) void {
        for (self.errors.items) |error_msg| {
            self.errors.allocator.free(error_msg);
        }
        self.errors.deinit();
    }
    
    /// Add an error message
    pub fn addError(self: *BenchmarkResults, error_msg: []const u8) !void {
        const msg_copy = try self.errors.allocator.dupe(u8, error_msg);
        try self.errors.append(msg_copy);
    }
    
    /// Print benchmark results
    pub fn print(self: *const BenchmarkResults, writer: anytype) !void {
        try writer.print("Benchmark Results:\n", .{});
        try writer.print("  Duration: {d:.2} seconds\n", .{self.duration_seconds});
        try writer.print("  Requests: {d}\n", .{self.requests});
        try writer.print("  Successful: {d} ({d:.2}%)\n", .{ 
            self.successful_requests, 
            if (self.requests > 0) @as(f64, @floatFromInt(self.successful_requests)) / @as(f64, @floatFromInt(self.requests)) * 100 else 0 
        });
        try writer.print("  Failed: {d} ({d:.2}%)\n", .{ 
            self.failed_requests, 
            if (self.requests > 0) @as(f64, @floatFromInt(self.failed_requests)) / @as(f64, @floatFromInt(self.requests)) * 100 else 0 
        });
        try writer.print("  Requests/second: {d:.2}\n", .{self.requests_per_second});
        try writer.print("  Latency:\n", .{});
        try writer.print("    Average: {d:.2} ms\n", .{self.avg_latency_ms});
        try writer.print("    Minimum: {d:.2} ms\n", .{self.min_latency_ms});
        try writer.print("    Maximum: {d:.2} ms\n", .{self.max_latency_ms});
        try writer.print("    p50: {d:.2} ms\n", .{self.p50_latency_ms});
        try writer.print("    p90: {d:.2} ms\n", .{self.p90_latency_ms});
        try writer.print("    p99: {d:.2} ms\n", .{self.p99_latency_ms});
        try writer.print("  Transfer:\n", .{});
        try writer.print("    Total: {d:.2} MB\n", .{@as(f64, @floatFromInt(self.bytes_received)) / (1024 * 1024)});
        try writer.print("    Rate: {d:.2} MB/s\n", .{self.transfer_rate_bps / (1024 * 1024)});
        
        if (self.errors.items.len > 0) {
            try writer.print("  Errors:\n", .{});
            for (self.errors.items) |error_msg| {
                try writer.print("    - {s}\n", .{error_msg});
            }
        }
    }
    
    /// Save benchmark results to a file
    pub fn saveToFile(self: *const BenchmarkResults, file_path: []const u8) !void {
        const file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();
        
        try self.print(file.writer());
    }
};

/// Run a benchmark
pub fn runBenchmark(allocator: std.mem.Allocator, config: BenchmarkConfig) !BenchmarkResults {
    return switch (config.protocol) {
        .http1, .http2 => try http.runHttpBenchmark(allocator, config),
        .websocket => try websocket.runWebSocketBenchmark(allocator, config),
    };
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
        .url = "http://localhost:8000/",
        .connections = 10000,
        .duration_seconds = 10,
        .concurrency = 100,
        .keep_alive = true,
        .protocol = .http1,
        .request_size = 0,
        .response_size = 0,
        .request_rate = 0,
        .output_file = null,
        .verbose = false,
    };
    
    // Parse arguments
    if (args.len > 1) {
        config.url = args[1];
    }
    
    if (args.len > 2) {
        config.connections = try std.fmt.parseInt(u32, args[2], 10);
    }
    
    if (args.len > 3) {
        config.duration_seconds = try std.fmt.parseInt(u32, args[3], 10);
    }
    
    if (args.len > 4) {
        config.concurrency = try std.fmt.parseInt(u32, args[4], 10);
    }
    
    if (args.len > 5) {
        config.keep_alive = (try std.fmt.parseInt(u8, args[5], 10)) != 0;
    }
    
    if (args.len > 6) {
        const protocol_str = args[6];
        if (std.mem.eql(u8, protocol_str, "http1")) {
            config.protocol = .http1;
        } else if (std.mem.eql(u8, protocol_str, "http2")) {
            config.protocol = .http2;
        } else if (std.mem.eql(u8, protocol_str, "websocket")) {
            config.protocol = .websocket;
        } else {
            std.debug.print("Invalid protocol: {s}\n", .{protocol_str});
            return error.InvalidProtocol;
        }
    }
    
    if (args.len > 7) {
        config.output_file = args[7];
    }
    
    if (args.len > 8) {
        config.verbose = (try std.fmt.parseInt(u8, args[8], 10)) != 0;
    }
    
    // Print benchmark configuration
    std.debug.print("Benchmark Configuration:\n", .{});
    std.debug.print("  URL: {s}\n", .{config.url});
    std.debug.print("  Protocol: {s}\n", .{@tagName(config.protocol)});
    std.debug.print("  Connections: {d}\n", .{config.connections});
    std.debug.print("  Duration: {d} seconds\n", .{config.duration_seconds});
    std.debug.print("  Concurrency: {d}\n", .{config.concurrency});
    std.debug.print("  Keep-Alive: {}\n", .{config.keep_alive});
    std.debug.print("  Output File: {s}\n", .{config.output_file orelse "stdout"});
    std.debug.print("  Verbose: {}\n", .{config.verbose});
    std.debug.print("\n", .{});
    
    // Run benchmark
    var results = try runBenchmark(allocator, config);
    defer results.deinit();
    
    // Print results
    try results.print(std.io.getStdOut().writer());
    
    // Save results to file if specified
    if (config.output_file) |file_path| {
        try results.saveToFile(file_path);
        std.debug.print("\nResults saved to {s}\n", .{file_path});
    }
}
