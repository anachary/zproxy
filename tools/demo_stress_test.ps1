# PowerShell script to run a demonstration stress test

# Create output directory
$OUTPUT_DIR = "stress_test_results"
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null
}

# Start the mock server in a separate process
Write-Host "Starting mock server..."
$mockServerProcess = Start-Process -FilePath ".\mock_server.exe" -PassThru -NoNewWindow

# Wait for the server to start
Start-Sleep -Seconds 2

# Define concurrency levels for the demo
$concurrencyLevels = @(100, 500, 1000)

foreach ($level in $concurrencyLevels) {
    Write-Host "Running benchmark with concurrency level: $level..."
    
    # Run the benchmark
    & .\simple_benchmark.exe `
        --host "127.0.0.1" `
        --port 8080 `
        --duration 5 `
        --concurrency $level `
        --no-http
    
    Write-Host ""
    
    # Allow system to recover between tests
    Start-Sleep -Seconds 2
}

# Stop the mock server
Write-Host "Stopping mock server..."
Stop-Process -Id $mockServerProcess.Id -Force

Write-Host "Stress test completed."
