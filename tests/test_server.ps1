# ZProxy Test Script
param (
    [string]$ConfigFile = "examples/basic_proxy.json",
    [switch]$Build = $false
)

# Set working directory to the script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent $scriptDir)

# Build the project if requested
if ($Build) {
    Write-Host "Building ZProxy..." -ForegroundColor Cyan
    zig build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "Build successful" -ForegroundColor Green
}

# Run tests
Write-Host "Running ZProxy tests..." -ForegroundColor Cyan
zig build test
if ($LASTEXITCODE -ne 0) {
    Write-Host "Tests failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "Tests passed" -ForegroundColor Green

# Start a mock server for testing
$mockServerPort = 8080
$mockServer = Start-Process -FilePath "powershell" -ArgumentList "-Command `"& { `$listener = New-Object System.Net.HttpListener; `$listener.Prefixes.Add('http://localhost:$mockServerPort/'); `$listener.Start(); Write-Host 'Mock server started on port $mockServerPort'; while (`$listener.IsListening) { `$context = `$listener.GetContext(); `$response = `$context.Response; `$response.ContentType = 'text/plain'; `$buffer = [System.Text.Encoding]::UTF8.GetBytes('Hello from mock server'); `$response.ContentLength64 = `$buffer.Length; `$response.OutputStream.Write(`$buffer, 0, `$buffer.Length); `$response.OutputStream.Close(); } }`"" -PassThru -NoNewWindow
Start-Sleep -Seconds 2

# Start ZProxy
Write-Host "Starting ZProxy with configuration: $ConfigFile" -ForegroundColor Cyan
$zproxy = Start-Process -FilePath "zig" -ArgumentList "build run -- $ConfigFile" -PassThru -NoNewWindow
Start-Sleep -Seconds 2

try {
    # Test the proxy
    Write-Host "Testing proxy..." -ForegroundColor Cyan
    $response = Invoke-WebRequest -Uri "http://localhost:8000/api" -Method GET
    
    if ($response.StatusCode -eq 200) {
        Write-Host "Proxy test successful" -ForegroundColor Green
        Write-Host "Response: $($response.Content)" -ForegroundColor Green
    } else {
        Write-Host "Proxy test failed with status code $($response.StatusCode)" -ForegroundColor Red
    }
} catch {
    Write-Host "Error testing proxy: $_" -ForegroundColor Red
} finally {
    # Stop ZProxy
    if ($zproxy -ne $null) {
        Stop-Process -Id $zproxy.Id -Force
        Write-Host "ZProxy stopped" -ForegroundColor Cyan
    }
    
    # Stop mock server
    if ($mockServer -ne $null) {
        Stop-Process -Id $mockServer.Id -Force
        Write-Host "Mock server stopped" -ForegroundColor Cyan
    }
}
