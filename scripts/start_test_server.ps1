# Start a simple HTTP server for benchmarking
param (
    [int]$Port = 8080
)

Write-Host "Starting test HTTP server on port $Port..." -ForegroundColor Cyan

# Create a simple HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host "Server started. Press Ctrl+C to stop." -ForegroundColor Green

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        
        # Get request details
        $request = $context.Request
        $response = $context.Response
        
        # Log request
        Write-Host "$($request.HttpMethod) $($request.Url.PathAndQuery)" -ForegroundColor Yellow
        
        # Prepare response
        $responseString = "Hello from test server!"
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseString)
        
        # Set response details
        $response.ContentLength64 = $buffer.Length
        $response.ContentType = "text/plain"
        
        # Send response
        $output = $response.OutputStream
        $output.Write($buffer, 0, $buffer.Length)
        $output.Close()
    }
}
finally {
    # Stop the listener
    $listener.Stop()
    Write-Host "Server stopped." -ForegroundColor Cyan
}
