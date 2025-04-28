# Run All Benchmarks Script
param (
    [string]$ConfigFile = "examples/basic_proxy.json",
    [switch]$Build = $false,
    [switch]$GenerateReport = $true
)

# Set working directory to the script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Create results directory
$resultsDir = "results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

# Get timestamp for results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

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

# Run HTTP/1.1 benchmark
Write-Host "Running HTTP/1.1 benchmark..." -ForegroundColor Cyan
& "$scriptDir\http\http1_benchmark.ps1" -ConfigFile $ConfigFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "HTTP/1.1 benchmark failed with exit code $LASTEXITCODE" -ForegroundColor Red
} else {
    Write-Host "HTTP/1.1 benchmark completed successfully" -ForegroundColor Green
}

# Run HTTP/2 benchmark
Write-Host "Running HTTP/2 benchmark..." -ForegroundColor Cyan
& "$scriptDir\http\http2_benchmark.ps1" -ConfigFile $ConfigFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "HTTP/2 benchmark failed with exit code $LASTEXITCODE" -ForegroundColor Red
} else {
    Write-Host "HTTP/2 benchmark completed successfully" -ForegroundColor Green
}

# Run WebSocket benchmark
Write-Host "Running WebSocket benchmark..." -ForegroundColor Cyan
& "$scriptDir\websocket\websocket_benchmark.ps1" -ConfigFile $ConfigFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "WebSocket benchmark failed with exit code $LASTEXITCODE" -ForegroundColor Red
} else {
    Write-Host "WebSocket benchmark completed successfully" -ForegroundColor Green
}

# Run comparison benchmark
Write-Host "Running comparison benchmark..." -ForegroundColor Cyan
& "$scriptDir\tools\compare_proxies.ps1" -ConfigFile $ConfigFile
if ($LASTEXITCODE -ne 0) {
    Write-Host "Comparison benchmark failed with exit code $LASTEXITCODE" -ForegroundColor Red
} else {
    Write-Host "Comparison benchmark completed successfully" -ForegroundColor Green
}

# Generate report if requested
if ($GenerateReport) {
    Write-Host "Generating benchmark report..." -ForegroundColor Cyan
    $reportFile = "..\docs\reports\performance_report_$timestamp.md"
    & "$scriptDir\tools\generate_report.ps1" -ResultsDir "$scriptDir\results" -OutputFile $reportFile -Title "ZProxy Performance Report - $timestamp"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Report generation failed with exit code $LASTEXITCODE" -ForegroundColor Red
    } else {
        Write-Host "Report generated successfully: $reportFile" -ForegroundColor Green
    }
}
