# ZProxy Benchmark Script
param (
    [string]$Url = "http://localhost:8000/",
    [int]$Connections = 10000,
    [int]$Duration = 10,
    [int]$Concurrency = 100,
    [switch]$KeepAlive = $true,
    [string]$Protocol = "http1",
    [string]$OutputFile,
    [switch]$Verbose = $false,
    [switch]$Build = $false
)

# Set working directory to the script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent $scriptDir)

# Create results directory if output file is specified
if ($OutputFile) {
    $outputDir = Split-Path -Parent $OutputFile
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir | Out-Null
    }
}

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

# Convert Verbose to integer
$verboseInt = if ($Verbose) { 1 } else { 0 }

# Run the benchmark
Write-Host "Running benchmark against $Url" -ForegroundColor Cyan
Write-Host "Connections: $Connections, Duration: $Duration seconds, Concurrency: $Concurrency, Protocol: $Protocol, Keep-Alive: $KeepAlive" -ForegroundColor Cyan

$benchmarkArgs = @(
    $Url,
    $Connections,
    $Duration,
    $Concurrency,
    $keepAliveInt,
    $Protocol
)

if ($OutputFile) {
    $benchmarkArgs += $OutputFile
}

$benchmarkArgs += $verboseInt

zig build benchmark -- $benchmarkArgs

# Check exit code
if ($LASTEXITCODE -ne 0) {
    Write-Host "Benchmark failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

# Print success message
if ($OutputFile) {
    Write-Host "Benchmark results saved to $OutputFile" -ForegroundColor Green
} else {
    Write-Host "Benchmark completed successfully" -ForegroundColor Green
}
