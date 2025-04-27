# Simple script to run a stress test

# Build the benchmark tools
Write-Host "Building benchmark tools..."
& zig build-exe tools/simple_benchmark.zig -OReleaseFast
& zig build-exe tools/mock_server.zig -OReleaseFast

# Start the mock server in a separate process
Write-Host "Starting mock server..."
$mockServerProcess = Start-Process -FilePath ".\mock_server.exe" -PassThru -NoNewWindow

# Wait for the server to start
Start-Sleep -Seconds 2

# Run the benchmark with increasing concurrency
$concurrencyLevels = @(100, 500, 1000, 2000)

foreach ($level in $concurrencyLevels) {
    Write-Host "Running benchmark with concurrency level: $level..."
    
    & .\simple_benchmark.exe `
        --host "127.0.0.1" `
        --port 8080 `
        --duration 5 `
        --concurrency $level `
        --no-http
    
    Write-Host ""
}

# Stop the mock server
Write-Host "Stopping mock server..."
Stop-Process -Id $mockServerProcess.Id -Force

Write-Host "Stress test completed."
