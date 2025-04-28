# HTTP/2 Benchmark Script
param (
    [string]$ConfigFile = "examples/basic_proxy.json",
    [int]$Connections = 10000,
    [int]$Duration = 10,
    [int]$Concurrency = 100,
    [switch]$KeepAlive = $true,
    [switch]$Build = $false
)

# Set working directory to the script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent (Split-Path -Parent $scriptDir))

# Create results directory
$resultsDir = "benchmarks/results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

# Get timestamp for results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$resultsFile = "$resultsDir/http2_$timestamp.txt"

# Start a mock backend server
$backendPort = 8080
$backendServer = Start-Process -FilePath "powershell" -ArgumentList "-Command `"& { `$listener = New-Object System.Net.HttpListener; `$listener.Prefixes.Add('http://localhost:$backendPort/'); `$listener.Start(); Write-Host 'Mock backend server started on port $backendPort'; while (`$listener.IsListening) { `$context = `$listener.GetContext(); `$response = `$context.Response; `$response.ContentType = 'text/plain'; `$buffer = [System.Text.Encoding]::UTF8.GetBytes('Hello from mock backend server'); `$response.ContentLength64 = `$buffer.Length; `$response.OutputStream.Write(`$buffer, 0, `$buffer.Length); `$response.OutputStream.Close(); } }`"" -PassThru -NoNewWindow
Start-Sleep -Seconds 2

# Start ZProxy
Write-Host "Starting ZProxy with configuration: $ConfigFile" -ForegroundColor Cyan
$zproxy = Start-Process -FilePath "zig" -ArgumentList "build run -- $ConfigFile" -PassThru -NoNewWindow
Start-Sleep -Seconds 2

try {
    # Run benchmark
    Write-Host "Running HTTP/2 benchmark..." -ForegroundColor Cyan
    
    # Build the benchmark tool if requested
    if ($Build) {
        Write-Host "Building benchmark tool..." -ForegroundColor Cyan
        zig build benchmark
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }
        Write-Host "Build successful" -ForegroundColor Green
    }
    
    # Convert KeepAlive to integer
    $keepAliveInt = if ($KeepAlive) { 1 } else { 0 }
    
    # Run the benchmark
    zig build benchmark -- "http://localhost:8000/" $Connections $Duration $Concurrency $keepAliveInt "http2" $resultsFile 0
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Benchmark failed with exit code $LASTEXITCODE" -ForegroundColor Red
    } else {
        Write-Host "Benchmark completed successfully. Results saved to $resultsFile" -ForegroundColor Green
    }
} finally {
    # Stop ZProxy
    if ($zproxy -ne $null) {
        Stop-Process -Id $zproxy.Id -Force
        Write-Host "ZProxy stopped" -ForegroundColor Cyan
    }
    
    # Stop mock server
    if ($backendServer -ne $null) {
        Stop-Process -Id $backendServer.Id -Force
        Write-Host "Mock server stopped" -ForegroundColor Cyan
    }
}
