# ZProxy Comparison Benchmark Script
param (
    [string]$ConfigFile = "examples/basic_proxy.json",
    [int]$Connections = 10000,
    [int]$Duration = 30,
    [int]$Concurrency = 100,
    [switch]$KeepAlive = $true,
    [string]$Protocol = "http1",
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
$resultsFile = "$resultsDir/comparison_$timestamp.md"

# Add header to results file
@"
# ZProxy Performance Comparison

## Test Configuration

- **Date**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
- **Connections**: $Connections
- **Duration**: $Duration seconds
- **Concurrency**: $Concurrency
- **Keep-Alive**: $KeepAlive
- **Protocol**: $Protocol

## Results

"@ | Out-File -FilePath $resultsFile

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

# Function to run a benchmark
function Run-Benchmark {
    param (
        [string]$Name,
        [string]$Url,
        [string]$OutputFile
    )
    
    Write-Host "Benchmarking $Name at $Url..." -ForegroundColor Cyan
    
    # Convert KeepAlive to integer
    $keepAliveInt = if ($KeepAlive) { 1 } else { 0 }
    
    # Run the benchmark
    zig build benchmark -- $Url $Connections $Duration $Concurrency $keepAliveInt $Protocol $OutputFile 0
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Benchmark failed with exit code $LASTEXITCODE" -ForegroundColor Red
        return $false
    }
    
    Write-Host "Benchmark complete" -ForegroundColor Green
    return $true
}

# Function to start a proxy
function Start-Proxy {
    param (
        [string]$Name,
        [string]$Command,
        [int]$Port,
        [int]$WaitSeconds = 2
    )
    
    Write-Host "Starting $Name on port $Port..." -ForegroundColor Cyan
    
    $process = Start-Process -FilePath "powershell" -ArgumentList "-Command `"$Command`"" -PassThru -NoNewWindow
    Start-Sleep -Seconds $WaitSeconds
    
    if ($process.HasExited) {
        Write-Host "$Name failed to start" -ForegroundColor Red
        return $null
    }
    
    Write-Host "$Name started with PID $($process.Id)" -ForegroundColor Green
    return $process
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
        "p99 Latency (ms)" = 0
        "Transfer Rate (MB/s)" = 0
    }
    
    if ($content -match "Requests/second: ([\d\.]+)") {
        $metrics["Requests/second"] = [double]$Matches[1]
    }
    
    if ($content -match "Average: ([\d\.]+) ms") {
        $metrics["Avg Latency (ms)"] = [double]$Matches[1]
    }
    
    if ($content -match "p99: ([\d\.]+) ms") {
        $metrics["p99 Latency (ms)"] = [double]$Matches[1]
    }
    
    if ($content -match "Rate: ([\d\.]+) MB/s") {
        $metrics["Transfer Rate (MB/s)"] = [double]$Matches[1]
    }
    
    return $metrics
}

# Start a mock backend server
$backendPort = 8080
$backendServer = Start-Proxy -Name "Mock Backend" -Port $backendPort -Command @"
`$listener = New-Object System.Net.HttpListener
`$listener.Prefixes.Add('http://localhost:$backendPort/')
`$listener.Start()
Write-Host 'Mock backend server started on port $backendPort'
while (`$listener.IsListening) {
    try {
        `$context = `$listener.GetContext()
        `$response = `$context.Response
        `$response.ContentType = 'text/plain'
        `$buffer = [System.Text.Encoding]::UTF8.GetBytes('Hello from mock backend server')
        `$response.ContentLength64 = `$buffer.Length
        `$response.OutputStream.Write(`$buffer, 0, `$buffer.Length)
        `$response.OutputStream.Close()
    } catch {
        Write-Host "Error: `$_"
    }
}
"@

if ($null -eq $backendServer) {
    Write-Host "Failed to start mock backend server" -ForegroundColor Red
    exit 1
}

# Array to store all processes
$processes = @($backendServer)

try {
    # Start ZProxy
    $zproxyPort = 8000
    $zproxyProcess = Start-Proxy -Name "ZProxy" -Port $zproxyPort -Command "zig build run -- $ConfigFile"
    
    if ($null -ne $zproxyProcess) {
        $processes += $zproxyProcess
        
        # Benchmark ZProxy
        $zproxyResultFile = "$resultsDir/zproxy_$timestamp.txt"
        $zproxySuccess = Run-Benchmark -Name "ZProxy" -Url "http://localhost:$zproxyPort/" -OutputFile $zproxyResultFile
        
        if ($zproxySuccess) {
            $zproxyMetrics = Extract-Metrics -ResultsFile $zproxyResultFile
            
            # Add ZProxy results to comparison file
            @"
### ZProxy

```
$(Get-Content -Path $zproxyResultFile -Raw)
```

"@ | Out-File -FilePath $resultsFile -Append
        }
    }
    
    # Start Nginx if available
    $nginxPort = 8001
    $nginxProcess = $null
    
    if (Test-Path "C:\nginx\nginx.exe") {
        # Create Nginx config
        $nginxConfigDir = "benchmarks/tools/nginx"
        if (-not (Test-Path $nginxConfigDir)) {
            New-Item -ItemType Directory -Path $nginxConfigDir | Out-Null
        }
        
        @"
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    server {
        listen $nginxPort;
        location / {
            proxy_pass http://localhost:$backendPort;
        }
    }
}
"@ | Out-File -FilePath "$nginxConfigDir/nginx.conf"
        
        $nginxProcess = Start-Proxy -Name "Nginx" -Port $nginxPort -Command "C:\nginx\nginx.exe -c $(Resolve-Path "$nginxConfigDir/nginx.conf")"
        
        if ($null -ne $nginxProcess) {
            $processes += $nginxProcess
            
            # Benchmark Nginx
            $nginxResultFile = "$resultsDir/nginx_$timestamp.txt"
            $nginxSuccess = Run-Benchmark -Name "Nginx" -Url "http://localhost:$nginxPort/" -OutputFile $nginxResultFile
            
            if ($nginxSuccess) {
                $nginxMetrics = Extract-Metrics -ResultsFile $nginxResultFile
                
                # Add Nginx results to comparison file
                @"
### Nginx

```
$(Get-Content -Path $nginxResultFile -Raw)
```

"@ | Out-File -FilePath $resultsFile -Append
            }
        }
    } else {
        Write-Host "Nginx not found, skipping" -ForegroundColor Yellow
    }
    
    # Start Envoy if available
    $envoyPort = 8002
    $envoyProcess = $null
    
    if (Test-Path "C:\envoy\envoy.exe") {
        # Create Envoy config
        $envoyConfigDir = "benchmarks/tools/envoy"
        if (-not (Test-Path $envoyConfigDir)) {
            New-Item -ItemType Directory -Path $envoyConfigDir | Out-Null
        }
        
        @"
static_resources:
  listeners:
  - address:
      socket_address:
        address: 0.0.0.0
        port_value: $envoyPort
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: backend
              domains:
              - "*"
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: backend_service
          http_filters:
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
  clusters:
  - name: backend_service
    connect_timeout: 0.25s
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: backend_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: localhost
                port_value: $backendPort
admin:
  access_log_path: "/dev/null"
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901
"@ | Out-File -FilePath "$envoyConfigDir/envoy.yaml"
        
        $envoyProcess = Start-Proxy -Name "Envoy" -Port $envoyPort -Command "C:\envoy\envoy.exe -c $(Resolve-Path "$envoyConfigDir/envoy.yaml")"
        
        if ($null -ne $envoyProcess) {
            $processes += $envoyProcess
            
            # Benchmark Envoy
            $envoyResultFile = "$resultsDir/envoy_$timestamp.txt"
            $envoySuccess = Run-Benchmark -Name "Envoy" -Url "http://localhost:$envoyPort/" -OutputFile $envoyResultFile
            
            if ($envoySuccess) {
                $envoyMetrics = Extract-Metrics -ResultsFile $envoyResultFile
                
                # Add Envoy results to comparison file
                @"
### Envoy

```
$(Get-Content -Path $envoyResultFile -Raw)
```

"@ | Out-File -FilePath $resultsFile -Append
            }
        }
    } else {
        Write-Host "Envoy not found, skipping" -ForegroundColor Yellow
    }
    
    # Create comparison table
    @"
## Comparison Table

| Proxy | Requests/second | Avg Latency (ms) | p99 Latency (ms) | Transfer Rate (MB/s) |
|-------|----------------|-----------------|-----------------|---------------------|
"@ | Out-File -FilePath $resultsFile -Append
    
    if ($zproxySuccess) {
        "| ZProxy | $($zproxyMetrics["Requests/second"]) | $($zproxyMetrics["Avg Latency (ms)"]) | $($zproxyMetrics["p99 Latency (ms)"]) | $($zproxyMetrics["Transfer Rate (MB/s)"]) |" | Out-File -FilePath $resultsFile -Append
    }
    
    if (($null -ne $nginxProcess) -and $nginxSuccess) {
        "| Nginx | $($nginxMetrics["Requests/second"]) | $($nginxMetrics["Avg Latency (ms)"]) | $($nginxMetrics["p99 Latency (ms)"]) | $($nginxMetrics["Transfer Rate (MB/s)"]) |" | Out-File -FilePath $resultsFile -Append
    }
    
    if (($null -ne $envoyProcess) -and $envoySuccess) {
        "| Envoy | $($envoyMetrics["Requests/second"]) | $($envoyMetrics["Avg Latency (ms)"]) | $($envoyMetrics["p99 Latency (ms)"]) | $($envoyMetrics["Transfer Rate (MB/s)"]) |" | Out-File -FilePath $resultsFile -Append
    }
    
    Write-Host "Comparison complete. Results saved to $resultsFile" -ForegroundColor Green
    
} finally {
    # Stop all processes
    foreach ($process in $processes) {
        if ($null -ne $process -and -not $process.HasExited) {
            Write-Host "Stopping process with PID $($process.Id)..." -ForegroundColor Cyan
            Stop-Process -Id $process.Id -Force
        }
    }
    
    # Stop Nginx properly if it was started
    if ($null -ne $nginxProcess) {
        if (Test-Path "C:\nginx\nginx.exe") {
            Start-Process -FilePath "C:\nginx\nginx.exe" -ArgumentList "-s stop" -NoNewWindow -Wait
        }
    }
}
