# benchmark.zig Documentation

## Overview

The `benchmark.zig` file implements a benchmarking tool for ZProxy. It measures performance metrics like requests per second, latency, and throughput by sending a large number of concurrent requests.

## Key Components

### Benchmark Configuration

```zig
const BenchmarkConfig = struct {
    url: []const u8,
    connections: u32,
    duration_seconds: u32,
    concurrency: u32,
    keep_alive: bool,
};
```

This structure holds the benchmark configuration:
- `url`: The URL to benchmark
- `connections`: Maximum number of connections to make
- `duration_seconds`: Duration of the benchmark in seconds
- `concurrency`: Number of concurrent connections
- `keep_alive`: Whether to use HTTP keep-alive

### Main Function

```zig
pub fn main() !void {
    // Parse command line arguments and run benchmark
}
```

The main function:
1. Initializes the memory allocator
2. Parses command line arguments
3. Sets up the benchmark configuration
4. Runs the benchmark
5. Prints the results

### Benchmark Runner

```zig
fn runBenchmark(allocator: std.mem.Allocator, config: BenchmarkConfig) !void {
    // Run the benchmark
}
```

This function runs the benchmark:
1. Parses the URL
2. Creates worker threads
3. Runs the benchmark for the specified duration
4. Collects and aggregates results
5. Calculates and prints statistics

### Thread Context and Results

```zig
const ThreadContext = struct {
    allocator: std.mem.Allocator,
    url: std.Uri,
    thread_id: usize,
    connections: u32,
    keep_alive: bool,
    semaphore: *std.Thread.Semaphore,
    connections_counter: *std.atomic.Atomic(u32),
    stop_flag: *std.atomic.Atomic(bool),
    result: *ThreadResult,
};

const ThreadResult = struct {
    requests: u64,
    errors: u64,
    bytes_received: u64,
    total_latency_ns: u64,
};
```

These structures hold thread-specific data:
- `ThreadContext`: Context for a worker thread
- `ThreadResult`: Results collected by a worker thread

### Worker Thread

```zig
fn workerThread(context: *ThreadContext) !void {
    // Make requests until stopped
}
```

This function is the main loop for worker threads:
1. Waits for a semaphore to limit concurrency
2. Makes a request
3. Updates results
4. Repeats until stopped

### Request Function

```zig
fn makeRequest(context: *ThreadContext, buffer: *[8192]u8) !void {
    // Make an HTTP request
}
```

This function makes an HTTP request:
1. Creates a TCP socket
2. Sets timeouts
3. Builds and sends an HTTP request
4. Reads and validates the response

## Zig Programming Principles

1. **Concurrency**: The benchmark uses multiple threads to simulate concurrent users.
2. **Thread Safety**: Atomic variables and semaphores are used to ensure thread safety.
3. **Error Handling**: Functions that can fail return errors using Zig's error union type.
4. **Memory Management**: The code carefully manages memory, allocating space for buffers and providing proper cleanup.
5. **Resource Safety**: The code uses `defer` statements to ensure resources are properly cleaned up, even if an error occurs.

## Usage Example

```bash
# Run with default settings (http://localhost:8000/, 10000 connections, 10 seconds, 100 concurrent connections, keep-alive)
zig build benchmark

# Run with custom settings
zig build benchmark -- http://example.com/ 100000 30 200 1
```

## Output Example

```
Benchmark Configuration:
  URL: http://localhost:8000/
  Connections: 10000
  Duration: 10 seconds
  Concurrency: 100
  Keep-Alive: true

Benchmark Results:
  Duration: 10.00 seconds
  Requests: 250000
  Errors: 0
  Requests/second: 25000.00
  Transfer rate: 75.00 MB/s
  Average latency: 4.00 ms
```
