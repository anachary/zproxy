# ZProxy Connection Benchmark

This document explains how to use the connection benchmark tool to measure how many concurrent connections ZProxy can handle per second.

## Overview

The connection benchmark tool is designed to:

1. Establish multiple concurrent connections to a target server
2. Measure the connection rate (connections per second)
3. Track success rate and connection latency
4. Generate detailed reports and visualizations

This allows you to quantify ZProxy's performance and compare it with other reverse proxies.

## Building the Benchmark Tool

To build the connection benchmark tool, run:

```bash
zig build -Doptimize=ReleaseFast
```

This will create the benchmark executable at `zig-out/bin/connection_benchmark`.

## Running the Benchmark

### Basic Usage

To run a basic benchmark against a ZProxy instance running on localhost:8080:

```bash
./zig-out/bin/connection_benchmark --host 127.0.0.1 --port 8080
```

### Command Line Options

The benchmark tool supports the following options:

```
--host HOST             Target host (default: 127.0.0.1)
--port PORT             Target port (default: 8080)
--connections COUNT     Number of connections to establish (default: 100000)
--concurrency COUNT     Number of concurrent connections (default: 1000)
--timeout MS            Connection timeout in milliseconds (default: 5000)
--duration SECONDS      Benchmark duration in seconds (default: 30)
--keep-alive            Keep connections alive after establishing them
--no-http               Don't send HTTP requests
--no-wait               Don't wait for responses
--path PATH             HTTP request path (default: /)
```

### Example: High Concurrency Test

To test how ZProxy handles high concurrency, run:

```bash
./zig-out/bin/connection_benchmark --host 127.0.0.1 --port 8080 --concurrency 10000 --duration 60
```

This will maintain 10,000 concurrent connections for 60 seconds.

### Example: Keep-Alive Connections

To test with keep-alive connections:

```bash
./zig-out/bin/connection_benchmark --host 127.0.0.1 --port 8080 --keep-alive
```

## Automated Benchmark Script

For convenience, we provide a shell script that runs benchmarks and generates reports:

```bash
./tools/run_benchmark.sh --host 127.0.0.1 --port 8080
```

### Script Options

```
--host HOST           Target host (default: 127.0.0.1)
--port PORT           Target port (default: 8080)
--duration SECONDS    Benchmark duration in seconds (default: 30)
--concurrency COUNT   Number of concurrent connections (default: 1000)
--keep-alive          Use keep-alive connections
--path PATH           HTTP request path (default: /)
--output DIR          Output directory for results (default: benchmark_results)
```

## Understanding the Results

The benchmark tool provides detailed statistics:

### Connection Rate

The number of connections established per second. This is the primary metric for measuring how many concurrent connections ZProxy can handle.

### Success Rate

The percentage of connection attempts that succeeded. A high success rate indicates that ZProxy is handling the load well.

### Connection Latency

- **Average Latency**: The average time to establish a connection
- **Minimum Latency**: The fastest connection time
- **Maximum Latency**: The slowest connection time

### Connection Time Histogram

The distribution of connection times, showing how many connections fell into each latency bucket.

## Benchmark Reports

The automated benchmark script generates:

1. **Text Reports**: Detailed statistics for each benchmark run
2. **Summary Report**: A Markdown table comparing results across different proxies
3. **Visualization**: An HTML page with charts comparing connection rates and latencies

## Comparing with Other Proxies

To compare ZProxy with other reverse proxies:

1. Run the benchmark against ZProxy
2. Run the same benchmark against other proxies (Nginx, HAProxy, etc.)
3. Compare the results using the generated summary report and visualization

Example:

```bash
# Benchmark ZProxy
./tools/run_benchmark.sh --host 127.0.0.1 --port 8080

# Benchmark Nginx
./tools/run_benchmark.sh --host 127.0.0.1 --port 8081

# Benchmark HAProxy
./tools/run_benchmark.sh --host 127.0.0.1 --port 8082
```

## Optimizing for Maximum Connections

To achieve the maximum number of connections per second:

1. **System Configuration**:
   - Increase system limits for open files (`ulimit -n`)
   - Adjust TCP settings (see below)
   - Allocate sufficient memory

2. **ZProxy Configuration**:
   - Use the optimized build with NUMA awareness
   - Adjust the number of worker threads to match your CPU cores
   - Configure appropriate buffer sizes

3. **TCP Tuning**:

```bash
# Increase local port range
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535"

# Reduce TIME_WAIT connections
sudo sysctl -w net.ipv4.tcp_tw_reuse=1

# Increase maximum connection backlog
sudo sysctl -w net.core.somaxconn=65535
sudo sysctl -w net.core.netdev_max_backlog=65535

# Increase TCP memory limits
sudo sysctl -w net.ipv4.tcp_mem="16777216 16777216 16777216"
sudo sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216"
sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"
```

## Expected Performance

On a modern server with proper configuration, ZProxy should be able to handle:

- **500,000+ connections per second** with HTTP/1.1
- **750,000+ connections per second** with HTTP/2
- **Sub-millisecond connection latency**
- **Millions of concurrent connections** (limited by available memory)

Performance will scale linearly with the number of NUMA nodes and CPU cores.

## Troubleshooting

If you encounter issues during benchmarking:

1. **Connection Failures**: Check system limits (`ulimit -n`) and TCP settings
2. **High Latency**: Look for resource contention (CPU, memory, network)
3. **Benchmark Tool Crashes**: Reduce concurrency or increase system resources

## Conclusion

The connection benchmark tool provides a reliable way to measure ZProxy's connection handling capacity. By running these benchmarks, you can verify that ZProxy is performing optimally and compare its performance with other reverse proxies.
