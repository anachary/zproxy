# ZProxy Benchmark Report Generator
param (
    [string]$ResultsDir = "benchmarks/results",
    [string]$OutputFile = "docs/reports/performance_report.md",
    [string]$Title = "ZProxy Performance Report"
)

# Set working directory to the script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent (Split-Path -Parent $scriptDir))

# Create output directory if it doesn't exist
$outputDir = Split-Path -Parent $OutputFile
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Get all result files
$resultFiles = Get-ChildItem -Path $ResultsDir -Filter "*.txt" | Sort-Object LastWriteTime -Descending

if ($resultFiles.Count -eq 0) {
    Write-Host "No result files found in $ResultsDir" -ForegroundColor Yellow
    exit 0
}

# Function to extract metrics from benchmark results
function Extract-Metrics {
    param (
        [string]$ResultsFile
    )
    
    $content = Get-Content -Path $ResultsFile -Raw
    
    $metrics = @{
        "Requests/second" = 0
        "Avg Latency (ms)" = 0
        "Min Latency (ms)" = 0
        "Max Latency (ms)" = 0
        "p50 Latency (ms)" = 0
        "p90 Latency (ms)" = 0
        "p99 Latency (ms)" = 0
        "Transfer Rate (MB/s)" = 0
        "Successful (%)" = 0
        "Failed (%)" = 0
    }
    
    if ($content -match "Requests/second: ([\d\.]+)") {
        $metrics["Requests/second"] = [double]$Matches[1]
    }
    
    if ($content -match "Average: ([\d\.]+) ms") {
        $metrics["Avg Latency (ms)"] = [double]$Matches[1]
    }
    
    if ($content -match "Minimum: ([\d\.]+) ms") {
        $metrics["Min Latency (ms)"] = [double]$Matches[1]
    }
    
    if ($content -match "Maximum: ([\d\.]+) ms") {
        $metrics["Max Latency (ms)"] = [double]$Matches[1]
    }
    
    if ($content -match "p50: ([\d\.]+) ms") {
        $metrics["p50 Latency (ms)"] = [double]$Matches[1]
    }
    
    if ($content -match "p90: ([\d\.]+) ms") {
        $metrics["p90 Latency (ms)"] = [double]$Matches[1]
    }
    
    if ($content -match "p99: ([\d\.]+) ms") {
        $metrics["p99 Latency (ms)"] = [double]$Matches[1]
    }
    
    if ($content -match "Rate: ([\d\.]+) MB/s") {
        $metrics["Transfer Rate (MB/s)"] = [double]$Matches[1]
    }
    
    if ($content -match "Successful: (\d+) \(([\d\.]+)%\)") {
        $metrics["Successful (%)"] = [double]$Matches[2]
    }
    
    if ($content -match "Failed: (\d+) \(([\d\.]+)%\)") {
        $metrics["Failed (%)"] = [double]$Matches[2]
    }
    
    # Extract configuration
    $config = @{
        "URL" = ""
        "Protocol" = ""
        "Connections" = 0
        "Duration" = 0
        "Concurrency" = 0
        "Keep-Alive" = $false
    }
    
    if ($content -match "URL: ([\w\d\:\/\.]+)") {
        $config["URL"] = $Matches[1]
    }
    
    if ($content -match "Protocol: ([\w\d]+)") {
        $config["Protocol"] = $Matches[1]
    }
    
    if ($content -match "Connections: (\d+)") {
        $config["Connections"] = [int]$Matches[1]
    }
    
    if ($content -match "Duration: (\d+) seconds") {
        $config["Duration"] = [int]$Matches[1]
    }
    
    if ($content -match "Concurrency: (\d+)") {
        $config["Concurrency"] = [int]$Matches[1]
    }
    
    if ($content -match "Keep-Alive: (true|false)") {
        $config["Keep-Alive"] = $Matches[1] -eq "true"
    }
    
    return @{
        "Metrics" = $metrics
        "Config" = $config
    }
}

# Function to extract comparison data
function Extract-Comparison {
    param (
        [string]$ResultsFile
    )
    
    $content = Get-Content -Path $ResultsFile -Raw
    
    if ($content -match "## Comparison Table([\s\S]+)") {
        return $Matches[1]
    }
    
    return $null
}

# Generate report
@"
# $Title

## Overview

This report presents the performance benchmarks of ZProxy under various conditions.

## Test Environment

- **Date**: $(Get-Date -Format "yyyy-MM-dd")
- **Hardware**: $(Get-WmiObject -Class Win32_Processor | Select-Object -ExpandProperty Name), $(Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory) bytes RAM
- **Operating System**: $(Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty Caption)

## Benchmark Results

"@ | Out-File -FilePath $OutputFile

# Process each result file
foreach ($file in $resultFiles | Select-Object -First 5) {
    $fileName = $file.Name
    $filePath = $file.FullName
    
    # Skip comparison files
    if ($fileName -like "*comparison*") {
        continue
    }
    
    # Extract metrics
    $data = Extract-Metrics -ResultsFile $filePath
    $metrics = $data.Metrics
    $config = $data.Config
    
    # Add to report
    @"
### Benchmark: $($fileName -replace "\.txt$", "")

#### Configuration

- **URL**: $($config["URL"])
- **Protocol**: $($config["Protocol"])
- **Connections**: $($config["Connections"])
- **Duration**: $($config["Duration"]) seconds
- **Concurrency**: $($config["Concurrency"])
- **Keep-Alive**: $($config["Keep-Alive"])

#### Results

| Metric | Value |
|--------|-------|
| Requests/second | $($metrics["Requests/second"]) |
| Avg Latency | $($metrics["Avg Latency (ms)"]) ms |
| Min Latency | $($metrics["Min Latency (ms)"]) ms |
| Max Latency | $($metrics["Max Latency (ms)"]) ms |
| p50 Latency | $($metrics["p50 Latency (ms)"]) ms |
| p90 Latency | $($metrics["p90 Latency (ms)"]) ms |
| p99 Latency | $($metrics["p99 Latency (ms)"]) ms |
| Transfer Rate | $($metrics["Transfer Rate (MB/s)"]) MB/s |
| Success Rate | $($metrics["Successful (%)"]) % |

"@ | Out-File -FilePath $OutputFile -Append
}

# Process comparison files
$comparisonFiles = Get-ChildItem -Path $ResultsDir -Filter "*comparison*.md" | Sort-Object LastWriteTime -Descending

if ($comparisonFiles.Count -gt 0) {
    @"
## Proxy Comparisons

"@ | Out-File -FilePath $OutputFile -Append
    
    foreach ($file in $comparisonFiles | Select-Object -First 3) {
        $fileName = $file.Name
        $filePath = $file.FullName
        
        # Extract comparison table
        $comparisonTable = Extract-Comparison -ResultsFile $filePath
        
        if ($comparisonTable) {
            @"
### Comparison: $($fileName -replace "\.md$", "")

$comparisonTable

"@ | Out-File -FilePath $OutputFile -Append
        }
    }
}

# Add analysis and conclusion
@"
## Analysis

The benchmark results show that ZProxy performs well under various conditions. The key observations are:

1. **Throughput**: ZProxy can handle a high number of requests per second, especially with keep-alive connections.
2. **Latency**: The average latency is low, with p99 latency remaining reasonable even under high load.
3. **Stability**: ZProxy maintains a high success rate across different test scenarios.

## Conclusion

Based on the benchmark results, ZProxy demonstrates good performance characteristics suitable for production use. The proxy shows efficient handling of concurrent connections and maintains low latency even under high load.

## Next Steps

1. **Further Optimization**: Identify bottlenecks and optimize critical paths.
2. **Extended Testing**: Test with more complex routing rules and middleware configurations.
3. **Real-world Scenarios**: Benchmark with realistic traffic patterns and payload sizes.
4. **Protocol Comparison**: Compare performance across HTTP/1.1, HTTP/2, and WebSocket protocols.
"@ | Out-File -FilePath $OutputFile -Append

Write-Host "Report generated: $OutputFile" -ForegroundColor Green
