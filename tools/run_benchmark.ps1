# PowerShell script to run connection benchmarks against zproxy and other proxies for comparison

# Default values
$HOST = "127.0.0.1"
$PORT = 8080
$DURATION = 30
$CONCURRENCY = 1000
$KEEP_ALIVE = $false
$PATH = "/"
$OUTPUT_DIR = "benchmark_results"

# Parse command line arguments
for ($i = 0; $i -lt $args.Count; $i++) {
    switch ($args[$i]) {
        "--host" {
            $HOST = $args[++$i]
        }
        "--port" {
            $PORT = [int]$args[++$i]
        }
        "--duration" {
            $DURATION = [int]$args[++$i]
        }
        "--concurrency" {
            $CONCURRENCY = [int]$args[++$i]
        }
        "--keep-alive" {
            $KEEP_ALIVE = $true
        }
        "--path" {
            $PATH = $args[++$i]
        }
        "--output" {
            $OUTPUT_DIR = $args[++$i]
        }
        default {
            Write-Host "Unknown option: $($args[$i])"
            exit 1
        }
    }
}

# Create output directory
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null
}

# Function to run a benchmark
function Run-Benchmark {
    param (
        [string]$name,
        [string]$host,
        [int]$port
    )
    
    $keep_alive_flag = ""
    
    if ($KEEP_ALIVE) {
        $keep_alive_flag = "--keep-alive"
    }
    
    Write-Host "Running benchmark against $name ($host`:$port)..."
    
    # Run the benchmark
    $output_file = "$OUTPUT_DIR\${name}_results.txt"
    
    & .\zig-out\bin\connection_benchmark.exe `
        --host $host `
        --port $port `
        --duration $DURATION `
        --concurrency $CONCURRENCY `
        --path $PATH `
        $keep_alive_flag | Tee-Object -FilePath $output_file
        
    Write-Host "Benchmark for $name completed."
    Write-Host "Results saved to $output_file"
    Write-Host ""
}

# Build the benchmark tool
Write-Host "Building connection benchmark tool..."
& zig build -Doptimize=ReleaseFast

# Run benchmarks
Run-Benchmark "zproxy" $HOST $PORT

# Generate summary report
Write-Host "Generating summary report..."

# Create report header
@"
# Connection Benchmark Summary

## Test Configuration
- Duration: $DURATION seconds
- Concurrency: $CONCURRENCY connections
- Keep-alive: $KEEP_ALIVE
- Path: $PATH

## Results

| Proxy | Connections/sec | Success Rate | Avg Latency (ms) | Min Latency (ms) | Max Latency (ms) |
|-------|----------------|--------------|------------------|------------------|------------------|
"@ | Out-File -FilePath "$OUTPUT_DIR\summary.md"

# Extract results from each benchmark
Get-ChildItem -Path $OUTPUT_DIR -Filter "*_results.txt" | ForEach-Object {
    $name = $_.BaseName -replace "_results$", ""
    
    # Extract metrics
    $content = Get-Content $_.FullName
    $conn_rate = ($content | Select-String "Connection rate:").Line -replace ".*Connection rate: ([0-9.]+).*", '$1'
    $success_rate = ($content | Select-String "Success rate:").Line -replace ".*Success rate: ([0-9.]+).*", '$1'
    $avg_latency = ($content | Select-String "Average connection time:").Line -replace ".*Average connection time: ([0-9.]+).*", '$1'
    $min_latency = ($content | Select-String "Min connection time:").Line -replace ".*Min connection time: ([0-9.]+).*", '$1'
    $max_latency = ($content | Select-String "Max connection time:").Line -replace ".*Max connection time: ([0-9.]+).*", '$1'
    
    # Add to summary
    "| $name | $conn_rate | $success_rate | $avg_latency | $min_latency | $max_latency |" | Out-File -FilePath "$OUTPUT_DIR\summary.md" -Append
}

Write-Host "Summary report generated at $OUTPUT_DIR\summary.md"

# Create a simple HTML visualization
@"
<!DOCTYPE html>
<html>
<head>
  <title>Connection Benchmark Visualization</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .chart-container { width: 800px; height: 400px; margin-bottom: 30px; }
  </style>
</head>
<body>
  <h1>Connection Benchmark Visualization</h1>
  
  <h2>Connections per Second</h2>
  <div class="chart-container">
    <canvas id="connectionRateChart"></canvas>
  </div>
  
  <h2>Connection Latency (ms)</h2>
  <div class="chart-container">
    <canvas id="latencyChart"></canvas>
  </div>
  
  <script>
    // Data
    const proxies = [
"@ | Out-File -FilePath "$OUTPUT_DIR\visualization.html"

# Add proxy names
Get-ChildItem -Path $OUTPUT_DIR -Filter "*_results.txt" | ForEach-Object {
    $name = $_.BaseName -replace "_results$", ""
    "      '$name'," | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append
}

@"
    ];
    
    const connectionRates = [
"@ | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append

# Add connection rates
Get-ChildItem -Path $OUTPUT_DIR -Filter "*_results.txt" | ForEach-Object {
    $content = Get-Content $_.FullName
    $conn_rate = ($content | Select-String "Connection rate:").Line -replace ".*Connection rate: ([0-9.]+).*", '$1'
    "      $conn_rate," | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append
}

@"
    ];
    
    const avgLatencies = [
"@ | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append

# Add average latencies
Get-ChildItem -Path $OUTPUT_DIR -Filter "*_results.txt" | ForEach-Object {
    $content = Get-Content $_.FullName
    $avg_latency = ($content | Select-String "Average connection time:").Line -replace ".*Average connection time: ([0-9.]+).*", '$1'
    "      $avg_latency," | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append
}

@"
    ];
    
    const minLatencies = [
"@ | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append

# Add min latencies
Get-ChildItem -Path $OUTPUT_DIR -Filter "*_results.txt" | ForEach-Object {
    $content = Get-Content $_.FullName
    $min_latency = ($content | Select-String "Min connection time:").Line -replace ".*Min connection time: ([0-9.]+).*", '$1'
    "      $min_latency," | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append
}

@"
    ];
    
    const maxLatencies = [
"@ | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append

# Add max latencies
Get-ChildItem -Path $OUTPUT_DIR -Filter "*_results.txt" | ForEach-Object {
    $content = Get-Content $_.FullName
    $max_latency = ($content | Select-String "Max connection time:").Line -replace ".*Max connection time: ([0-9.]+).*", '$1'
    "      $max_latency," | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append
}

@"
    ];
    
    // Create charts
    const connectionRateChart = new Chart(
      document.getElementById('connectionRateChart'),
      {
        type: 'bar',
        data: {
          labels: proxies,
          datasets: [{
            label: 'Connections per Second',
            data: connectionRates,
            backgroundColor: 'rgba(54, 162, 235, 0.5)',
            borderColor: 'rgba(54, 162, 235, 1)',
            borderWidth: 1
          }]
        },
        options: {
          scales: {
            y: {
              beginAtZero: true,
              title: {
                display: true,
                text: 'Connections/sec'
              }
            }
          }
        }
      }
    );
    
    const latencyChart = new Chart(
      document.getElementById('latencyChart'),
      {
        type: 'bar',
        data: {
          labels: proxies,
          datasets: [
            {
              label: 'Min Latency',
              data: minLatencies,
              backgroundColor: 'rgba(75, 192, 192, 0.5)',
              borderColor: 'rgba(75, 192, 192, 1)',
              borderWidth: 1
            },
            {
              label: 'Avg Latency',
              data: avgLatencies,
              backgroundColor: 'rgba(255, 159, 64, 0.5)',
              borderColor: 'rgba(255, 159, 64, 1)',
              borderWidth: 1
            },
            {
              label: 'Max Latency',
              data: maxLatencies,
              backgroundColor: 'rgba(255, 99, 132, 0.5)',
              borderColor: 'rgba(255, 99, 132, 1)',
              borderWidth: 1
            }
          ]
        },
        options: {
          scales: {
            y: {
              beginAtZero: true,
              title: {
                display: true,
                text: 'Latency (ms)'
              }
            }
          }
        }
      }
    );
  </script>
</body>
</html>
"@ | Out-File -FilePath "$OUTPUT_DIR\visualization.html" -Append

Write-Host "Visualization created at $OUTPUT_DIR\visualization.html"
Write-Host "Open it in a browser to view the charts."
