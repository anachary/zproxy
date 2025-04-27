# Simple script to run the benchmark

# Start the mock server
Start-Process -FilePath ".\mock_server.exe" -NoNewWindow

# Wait for the server to start
Start-Sleep -Seconds 2

# Run the benchmark
.\simple_benchmark.exe --duration 5 --concurrency 500

# Wait for user input before closing
Write-Host "Press Enter to exit..."
Read-Host
