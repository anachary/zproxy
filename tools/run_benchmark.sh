#!/bin/bash

# Script to run connection benchmarks against zproxy and other proxies for comparison

# Default values
HOST="127.0.0.1"
PORT=8080
DURATION=30
CONCURRENCY=1000
KEEP_ALIVE=false
PATH="/"
OUTPUT_DIR="benchmark_results"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --host)
      HOST="$2"
      shift 2
      ;;
    --port)
      PORT="$2"
      shift 2
      ;;
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --concurrency)
      CONCURRENCY="$2"
      shift 2
      ;;
    --keep-alive)
      KEEP_ALIVE=true
      shift
      ;;
    --path)
      PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to run a benchmark
run_benchmark() {
  local name=$1
  local host=$2
  local port=$3
  local keep_alive_flag=""
  
  if [ "$KEEP_ALIVE" = true ]; then
    keep_alive_flag="--keep-alive"
  fi
  
  echo "Running benchmark against $name ($host:$port)..."
  
  # Run the benchmark
  ./zig-out/bin/connection_benchmark \
    --host "$host" \
    --port "$port" \
    --duration "$DURATION" \
    --concurrency "$CONCURRENCY" \
    --path "$PATH" \
    $keep_alive_flag \
    | tee "$OUTPUT_DIR/${name}_results.txt"
    
  echo "Benchmark for $name completed."
  echo "Results saved to $OUTPUT_DIR/${name}_results.txt"
  echo ""
}

# Build the benchmark tool
echo "Building connection benchmark tool..."
zig build -Doptimize=ReleaseFast

# Run benchmarks
run_benchmark "zproxy" "$HOST" "$PORT"

# Generate summary report
echo "Generating summary report..."

# Create report header
cat > "$OUTPUT_DIR/summary.md" << EOF
# Connection Benchmark Summary

## Test Configuration
- Duration: $DURATION seconds
- Concurrency: $CONCURRENCY connections
- Keep-alive: $KEEP_ALIVE
- Path: $PATH

## Results

| Proxy | Connections/sec | Success Rate | Avg Latency (ms) | Min Latency (ms) | Max Latency (ms) |
|-------|----------------|--------------|------------------|------------------|------------------|
EOF

# Extract results from each benchmark
for result_file in "$OUTPUT_DIR"/*_results.txt; do
  name=$(basename "$result_file" _results.txt)
  
  # Extract metrics
  conn_rate=$(grep "Connection rate:" "$result_file" | awk '{print $3}')
  success_rate=$(grep "Success rate:" "$result_file" | awk '{print $3}')
  avg_latency=$(grep "Average connection time:" "$result_file" | awk '{print $4}')
  min_latency=$(grep "Min connection time:" "$result_file" | awk '{print $4}')
  max_latency=$(grep "Max connection time:" "$result_file" | awk '{print $4}')
  
  # Add to summary
  echo "| $name | $conn_rate | $success_rate | $avg_latency | $min_latency | $max_latency |" >> "$OUTPUT_DIR/summary.md"
done

echo "Summary report generated at $OUTPUT_DIR/summary.md"

# Create a simple HTML visualization
cat > "$OUTPUT_DIR/visualization.html" << EOF
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
EOF

# Add proxy names
for result_file in "$OUTPUT_DIR"/*_results.txt; do
  name=$(basename "$result_file" _results.txt)
  echo "      '$name'," >> "$OUTPUT_DIR/visualization.html"
done

cat >> "$OUTPUT_DIR/visualization.html" << EOF
    ];
    
    const connectionRates = [
EOF

# Add connection rates
for result_file in "$OUTPUT_DIR"/*_results.txt; do
  conn_rate=$(grep "Connection rate:" "$result_file" | awk '{print $3}')
  echo "      $conn_rate," >> "$OUTPUT_DIR/visualization.html"
done

cat >> "$OUTPUT_DIR/visualization.html" << EOF
    ];
    
    const avgLatencies = [
EOF

# Add average latencies
for result_file in "$OUTPUT_DIR"/*_results.txt; do
  avg_latency=$(grep "Average connection time:" "$result_file" | awk '{print $4}')
  echo "      $avg_latency," >> "$OUTPUT_DIR/visualization.html"
done

cat >> "$OUTPUT_DIR/visualization.html" << EOF
    ];
    
    const minLatencies = [
EOF

# Add min latencies
for result_file in "$OUTPUT_DIR"/*_results.txt; do
  min_latency=$(grep "Min connection time:" "$result_file" | awk '{print $4}')
  echo "      $min_latency," >> "$OUTPUT_DIR/visualization.html"
done

cat >> "$OUTPUT_DIR/visualization.html" << EOF
    ];
    
    const maxLatencies = [
EOF

# Add max latencies
for result_file in "$OUTPUT_DIR"/*_results.txt; do
  max_latency=$(grep "Max connection time:" "$result_file" | awk '{print $4}')
  echo "      $max_latency," >> "$OUTPUT_DIR/visualization.html"
done

cat >> "$OUTPUT_DIR/visualization.html" << EOF
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
EOF

echo "Visualization created at $OUTPUT_DIR/visualization.html"
echo "Open it in a browser to view the charts."
