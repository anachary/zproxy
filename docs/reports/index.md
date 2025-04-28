# ZProxy Benchmarking

This document describes the benchmarking system in ZProxy.

## Overview

ZProxy includes a comprehensive benchmarking system that can be used to measure and compare performance across different configurations and protocols.

## Benchmarking Tools

### Benchmark Client

The benchmark client is implemented in `benchmarks/benchmark.zig`. It provides a command-line interface for running benchmarks against ZProxy or other proxy servers.

```bash
zig build benchmark -- <url> <connections> <duration> <concurrency> <keep_alive> <protocol> [output_file] [verbose]
```

Parameters:
- `url`: The URL to benchmark
- `connections`: The number of connections to make
- `duration`: The duration of the benchmark in seconds
- `concurrency`: The number of concurrent connections
- `keep_alive`: Whether to use HTTP keep-alive (1=enabled, 0=disabled)
- `protocol`: The protocol to use (http1, http2, websocket)
- `output_file`: The file to write the results to (optional)
- `verbose`: Whether to print verbose output (1=enabled, 0=disabled) (optional)

### PowerShell Scripts

ZProxy includes several PowerShell scripts for running benchmarks:

- `scripts/run_benchmark.ps1`: Run a benchmark against a server
- `scripts/compare_proxies.ps1`: Compare ZProxy with other proxies
- `scripts/run_all_benchmarks.ps1`: Run all benchmarks and generate a report

#### Run Benchmark

```powershell
.\scripts\run_benchmark.ps1 -Url "http://localhost:8000/" -Connections 10000 -Duration 30 -Concurrency 100 -KeepAlive -Protocol http1 -OutputFile "results.txt"
```

Parameters:
- `-Url`: The URL to benchmark
- `-Connections`: The number of connections to make
- `-Duration`: The duration of the benchmark in seconds
- `-Concurrency`: The number of concurrent connections
- `-KeepAlive`: Whether to use HTTP keep-alive
- `-Protocol`: The protocol to use (http1, http2, websocket)
- `-OutputFile`: The file to write the results to (optional)
- `-Verbose`: Whether to print verbose output (optional)
- `-Build`: Whether to build the benchmark tool before running (optional)

#### Compare Proxies

```powershell
.\scripts\compare_proxies.ps1 -ConfigFile "examples/high_performance.json" -Connections 10000 -Duration 30 -Concurrency 100 -KeepAlive -Protocol http1
```

Parameters:
- `-ConfigFile`: The configuration file to use for ZProxy
- `-Connections`: The number of connections to make
- `-Duration`: The duration of the benchmark in seconds
- `-Concurrency`: The number of concurrent connections
- `-KeepAlive`: Whether to use HTTP keep-alive
- `-Protocol`: The protocol to use (http1, http2, websocket)
- `-Build`: Whether to build the benchmark tool before running (optional)

#### Run All Benchmarks

```powershell
.\scripts\run_all_benchmarks.ps1 -ConfigFile "examples/basic_proxy.json" -Build -GenerateReport
```

Parameters:
- `-ConfigFile`: The configuration file to use for ZProxy
- `-Build`: Whether to build the benchmark tool before running (optional)
- `-GenerateReport`: Whether to generate a report (optional)

## Benchmark Results

The benchmark results include the following metrics:

- **Requests**: The total number of requests
- **Successful Requests**: The number of successful requests
- **Failed Requests**: The number of failed requests
- **Requests per Second**: The number of requests per second
- **Latency**: The average, minimum, maximum, p50, p90, and p99 latency
- **Transfer Rate**: The transfer rate in bytes per second

Example output:

```
Benchmark Results:
  Duration: 5.00 seconds
  Requests: 10000
  Successful: 10000 (100.00%)
  Failed: 0 (0.00%)
  Requests/second: 2000.00
  Latency:
    Average: 5.00 ms
    Minimum: 1.00 ms
    Maximum: 20.00 ms
    p50: 4.00 ms
    p90: 8.00 ms
    p99: 15.00 ms
  Transfer:
    Total: 10.00 MB
    Rate: 2.00 MB/s
```

## Benchmark Reports

The benchmark reports are generated in Markdown format and stored in the `docs/reports/` directory. They include:

- **Overview**: A summary of the benchmark
- **Test Environment**: Information about the hardware and software used
- **Benchmark Results**: Detailed results for each benchmark
- **Proxy Comparisons**: Comparisons with other proxies
- **Analysis**: Analysis of the results
- **Conclusion**: Conclusions drawn from the results
- **Next Steps**: Recommendations for further optimization

Example report:

```markdown
# ZProxy Performance Report - 20230101_000000

## Overview

This report presents the performance benchmarks of ZProxy under various conditions.

## Test Environment

- **Date**: 2023-01-01
- **Hardware**: Intel Core i7-9700K, 32 GB RAM
- **Operating System**: Windows 10 Pro

## Benchmark Results

### Benchmark: http1_20230101_000000

#### Configuration

- **URL**: http://localhost:8000/
- **Protocol**: http1
- **Connections**: 10000
- **Duration**: 30 seconds
- **Concurrency**: 100
- **Keep-Alive**: true

#### Results

| Metric | Value |
|--------|-------|
| Requests/second | 2000.00 |
| Avg Latency | 5.00 ms |
| Min Latency | 1.00 ms |
| Max Latency | 20.00 ms |
| p50 Latency | 4.00 ms |
| p90 Latency | 8.00 ms |
| p99 Latency | 15.00 ms |
| Transfer Rate | 2.00 MB/s |
| Success Rate | 100.00 % |

## Proxy Comparisons

### Comparison: comparison_20230101_000000

| Proxy | Requests/second | Avg Latency (ms) | p99 Latency (ms) | Transfer Rate (MB/s) |
|-------|----------------|-----------------|-----------------|---------------------|
| ZProxy | 2000.00 | 5.00 | 15.00 | 2.00 |
| Nginx | 1800.00 | 5.50 | 16.00 | 1.80 |
| Envoy | 1700.00 | 6.00 | 17.00 | 1.70 |

## Analysis

The benchmark results show that ZProxy performs well under various conditions. The key observations are:

1. **Throughput**: ZProxy can handle a high number of requests per second, especially with keep-alive connections.
2. **Latency**: The average latency is low, with p99 latency remaining reasonable even under high load.
3. **Stability**: ZProxy maintains a high success rate across different test scenarios.

## Conclusion

Based on the benchmark results, ZProxy demonstrates good performance characteristics suitable for production use. The proxy shows efficient handling of concurrent connections and maintains low latency even under high load.

## Next Steps

1. **Further Optimization**: Identify bottlenecks and optimize critical paths.
2. **Extended Testing**: Test with more complex routing rules and middleware configurations.
3. **Real-world Scenarios**: Benchmark with realistic traffic patterns and payload sizes.
4. **Protocol Comparison**: Compare performance across HTTP/1.1, HTTP/2, and WebSocket protocols.
```

## Running Benchmarks

To run benchmarks:

1. Start ZProxy with the desired configuration
2. Run the benchmark client or script
3. Analyze the results

Example:

```bash
# Start ZProxy
zig build run -- examples/high_performance.json

# Run a benchmark
.\scripts\run_benchmark.ps1 -Url "http://localhost:8000/" -Connections 10000 -Duration 30 -Concurrency 100 -KeepAlive -Protocol http1 -OutputFile "results.txt"

# Compare with other proxies
.\scripts\compare_proxies.ps1 -ConfigFile examples/high_performance.json -Connections 10000 -Duration 30 -Concurrency 100 -KeepAlive -Protocol http1

# Run all benchmarks and generate a report
.\scripts\run_all_benchmarks.ps1 -ConfigFile examples/high_performance.json -Build -GenerateReport
```

## Benchmark Configuration

The benchmark configuration can be customized using the command-line parameters or the PowerShell script parameters.

### HTTP/1.1 Benchmarks

```powershell
.\scripts\run_benchmark.ps1 -Url "http://localhost:8000/" -Protocol http1 -Connections 10000 -Duration 30 -Concurrency 100 -KeepAlive
```

### HTTP/2 Benchmarks

```powershell
.\scripts\run_benchmark.ps1 -Url "http://localhost:8000/" -Protocol http2 -Connections 10000 -Duration 30 -Concurrency 100 -KeepAlive
```

### WebSocket Benchmarks

```powershell
.\scripts\run_benchmark.ps1 -Url "ws://localhost:8000/" -Protocol websocket -Connections 1000 -Duration 30 -Concurrency 100
```

## Benchmark Analysis

The benchmark results can be analyzed to identify performance bottlenecks and areas for optimization.

### Throughput Analysis

The throughput (requests per second) is a key metric for proxy performance. Higher throughput indicates better performance.

Factors that affect throughput:
- Connection concurrency
- Keep-alive connections
- Protocol overhead
- Request and response size
- CPU and memory usage
- Network latency

### Latency Analysis

The latency (response time) is another key metric for proxy performance. Lower latency indicates better performance.

Factors that affect latency:
- Connection establishment
- Request parsing
- Routing
- Middleware processing
- Upstream server response time
- Response generation
- Network latency

### Comparison Analysis

Comparing ZProxy with other proxies (Nginx, Envoy, etc.) provides insights into its relative performance.

Factors to consider in comparisons:
- Configuration differences
- Feature differences
- Deployment differences
- Hardware differences
- Network differences
