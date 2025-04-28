# Simple benchmark runner
param (
    [int]$ServerPort = 8080,
    [int]$Connections = 1000,
    [int]$Duration = 10,
    [int]$Concurrency = 10
)

# Set working directory to the script's directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Split-Path -Parent $scriptDir)

# Create results directory
$resultsDir = "benchmarks/results"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
}

# Get timestamp for results
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$resultsFile = "$resultsDir/simple_benchmark_$timestamp.txt"

# Start the test server
Write-Host "Starting test server..." -ForegroundColor Cyan
$serverProcess = Start-Process -FilePath "powershell" -ArgumentList "-File $scriptDir\start_test_server.ps1 -Port $ServerPort" -PassThru -NoNewWindow

# Wait for server to start
Start-Sleep -Seconds 2

try {
    # Run a simple HTTP benchmark using PowerShell
    Write-Host "Running benchmark..." -ForegroundColor Cyan
    
    # Create a stopwatch to measure time
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Create a counter for successful requests
    $successfulRequests = 0
    $failedRequests = 0
    
    # Create an array to store response times
    $responseTimes = @()
    
    # Create runspace pool for parallel execution
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $Concurrency)
    $runspacePool.Open()
    
    # Create a collection to hold the runspaces
    $runspaces = New-Object System.Collections.ArrayList
    
    # Function to make HTTP request
    $scriptBlock = {
        param($url)
        
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
            $sw.Stop()
            
            return @{
                Success = $true
                StatusCode = $response.StatusCode
                Time = $sw.ElapsedMilliseconds
                Length = $response.Content.Length
            }
        }
        catch {
            $sw.Stop()
            return @{
                Success = $false
                Error = $_.Exception.Message
                Time = $sw.ElapsedMilliseconds
            }
        }
    }
    
    # Start the benchmark
    $url = "http://localhost:$ServerPort/"
    $endTime = $stopwatch.ElapsedMilliseconds + ($Duration * 1000)
    
    Write-Host "Benchmarking $url for $Duration seconds with $Concurrency concurrent connections..." -ForegroundColor Cyan
    
    while ($stopwatch.ElapsedMilliseconds -lt $endTime) {
        # Check if we need to add more runspaces
        while ($runspaces.Count -lt $Concurrency -and $stopwatch.ElapsedMilliseconds -lt $endTime) {
            $powerShell = [powershell]::Create().AddScript($scriptBlock).AddArgument($url)
            $powerShell.RunspacePool = $runspacePool
            
            $runspace = @{}
            $runspace.PowerShell = $powerShell
            $runspace.Handle = $powerShell.BeginInvoke()
            
            $null = $runspaces.Add($runspace)
        }
        
        # Check for completed runspaces
        for ($i = 0; $i -lt $runspaces.Count; $i++) {
            $runspace = $runspaces[$i]
            
            if ($runspace.Handle.IsCompleted) {
                $result = $runspace.PowerShell.EndInvoke($runspace.Handle)
                
                if ($result.Success) {
                    $successfulRequests++
                    $responseTimes += $result.Time
                }
                else {
                    $failedRequests++
                }
                
                $runspace.PowerShell.Dispose()
                $runspaces.RemoveAt($i)
                $i--
            }
        }
        
        # Small sleep to prevent CPU hogging
        Start-Sleep -Milliseconds 10
    }
    
    # Wait for remaining runspaces to complete
    while ($runspaces.Count -gt 0) {
        for ($i = 0; $i -lt $runspaces.Count; $i++) {
            $runspace = $runspaces[$i]
            
            if ($runspace.Handle.IsCompleted) {
                $result = $runspace.PowerShell.EndInvoke($runspace.Handle)
                
                if ($result.Success) {
                    $successfulRequests++
                    $responseTimes += $result.Time
                }
                else {
                    $failedRequests++
                }
                
                $runspace.PowerShell.Dispose()
                $runspaces.RemoveAt($i)
                $i--
            }
        }
        
        # Small sleep to prevent CPU hogging
        Start-Sleep -Milliseconds 10
    }
    
    # Stop the stopwatch
    $stopwatch.Stop()
    
    # Calculate results
    $totalRequests = $successfulRequests + $failedRequests
    $requestsPerSecond = $totalRequests / $stopwatch.Elapsed.TotalSeconds
    
    # Calculate latency statistics
    $avgLatency = if ($responseTimes.Count -gt 0) { ($responseTimes | Measure-Object -Average).Average } else { 0 }
    $minLatency = if ($responseTimes.Count -gt 0) { ($responseTimes | Measure-Object -Minimum).Minimum } else { 0 }
    $maxLatency = if ($responseTimes.Count -gt 0) { ($responseTimes | Measure-Object -Maximum).Maximum } else { 0 }
    
    # Sort response times for percentiles
    $sortedTimes = $responseTimes | Sort-Object
    $p50Index = [math]::Floor($sortedTimes.Count * 0.5)
    $p90Index = [math]::Floor($sortedTimes.Count * 0.9)
    $p99Index = [math]::Floor($sortedTimes.Count * 0.99)
    
    $p50Latency = if ($sortedTimes.Count -gt 0) { $sortedTimes[$p50Index] } else { 0 }
    $p90Latency = if ($sortedTimes.Count -gt 0) { $sortedTimes[$p90Index] } else { 0 }
    $p99Latency = if ($sortedTimes.Count -gt 0) { $sortedTimes[$p99Index] } else { 0 }
    
    # Create results
    $results = @"
Benchmark Results:
  Duration: $($stopwatch.Elapsed.TotalSeconds.ToString("0.00")) seconds
  Requests: $totalRequests
  Successful: $successfulRequests ($([math]::Round($successfulRequests / $totalRequests * 100, 2))%)
  Failed: $failedRequests ($([math]::Round($failedRequests / $totalRequests * 100, 2))%)
  Requests/second: $([math]::Round($requestsPerSecond, 2))
  Latency:
    Average: $([math]::Round($avgLatency, 2)) ms
    Minimum: $([math]::Round($minLatency, 2)) ms
    Maximum: $([math]::Round($maxLatency, 2)) ms
    p50: $([math]::Round($p50Latency, 2)) ms
    p90: $([math]::Round($p90Latency, 2)) ms
    p99: $([math]::Round($p99Latency, 2)) ms
"@
    
    # Display results
    Write-Host $results -ForegroundColor Green
    
    # Save results to file
    $results | Out-File -FilePath $resultsFile
    Write-Host "Results saved to $resultsFile" -ForegroundColor Cyan
}
finally {
    # Stop the server
    if ($serverProcess -ne $null -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force
        Write-Host "Test server stopped." -ForegroundColor Cyan
    }
    
    # Close the runspace pool
    if ($runspacePool -ne $null) {
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
}
