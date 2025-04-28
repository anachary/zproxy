# Run All Benchmarks Script
param (
    [string]$ConfigFile = "examples/basic_proxy.json",
    [switch]$Build = $false,
    [switch]$GenerateReport = $true
)

# Set working directory to the script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent $scriptDir)

# Run all benchmarks
& "benchmarks/run_all_benchmarks.ps1" -ConfigFile $ConfigFile -Build:$Build -GenerateReport:$GenerateReport

# Check exit code
if ($LASTEXITCODE -ne 0) {
    Write-Host "Benchmarks failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "All benchmarks completed successfully" -ForegroundColor Green
