# WebSocket Benchmark Script
param (
    [string]$ConfigFile = "examples/basic_proxy.json",
    [int]$Connections = 1000,
    [int]$Duration = 10,
    [int]$Concurrency = 100,
    [int]$MessageSize = 128,
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
$resultsFile = "$resultsDir/websocket_$timestamp.txt"

# Start a mock WebSocket server
$backendPort = 8080
$backendServer = Start-Process -FilePath "powershell" -ArgumentList "-Command `"& {
    Add-Type -AssemblyName System.Net.WebSockets;
    
    function Start-WebSocketServer {
        param (
            [int]`$Port = 8080
        )
        
        `$listener = New-Object System.Net.HttpListener;
        `$listener.Prefixes.Add('http://localhost:' + `$Port + '/');
        `$listener.Start();
        
        Write-Host 'WebSocket server started on port ' `$Port;
        
        while (`$listener.IsListening) {
            `$context = `$listener.GetContext();
            
            if (`$context.Request.IsWebSocketRequest) {
                `$webSocketContext = `$context.AcceptWebSocketAsync().Result;
                `$webSocket = `$webSocketContext.WebSocket;
                
                `$buffer = New-Object byte[] 1024;
                
                while (`$webSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                    `$receiveResult = `$webSocket.ReceiveAsync(
                        (New-Object System.ArraySegment[byte] -ArgumentList @(,`$buffer)),
                        [System.Threading.CancellationToken]::None
                    ).Result;
                    
                    if (`$receiveResult.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                        `$webSocket.CloseAsync(
                            [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                            'Closing',
                            [System.Threading.CancellationToken]::None
                        ).Wait();
                    } else {
                        `$webSocket.SendAsync(
                            (New-Object System.ArraySegment[byte] -ArgumentList @(,`$buffer, 0, `$receiveResult.Count)),
                            `$receiveResult.MessageType,
                            `$receiveResult.EndOfMessage,
                            [System.Threading.CancellationToken]::None
                        ).Wait();
                    }
                }
                
                `$webSocket.Dispose();
            } else {
                `$context.Response.StatusCode = 400;
                `$context.Response.Close();
            }
        }
    }
    
    Start-WebSocketServer -Port $backendPort;
}`"" -PassThru -NoNewWindow
Start-Sleep -Seconds 2

# Start ZProxy
Write-Host "Starting ZProxy with configuration: $ConfigFile" -ForegroundColor Cyan
$zproxy = Start-Process -FilePath "zig" -ArgumentList "build run -- $ConfigFile" -PassThru -NoNewWindow
Start-Sleep -Seconds 2

try {
    # Run benchmark
    Write-Host "Running WebSocket benchmark..." -ForegroundColor Cyan
    
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
    
    # Run the benchmark
    zig build benchmark -- "ws://localhost:8000/" $Connections $Duration $Concurrency 0 "websocket" $resultsFile 0
    
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
