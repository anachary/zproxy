# main.zig Documentation

## Overview

The `main.zig` file serves as the entry point for the ZProxy server. It handles initialization, configuration loading, server startup, and graceful shutdown.

## Key Components

### Imports

```zig
const std = @import("std");
const config = @import("config/config.zig");
const server = @import("server/server.zig");
const logger = @import("utils/logger.zig");
```

These lines import the necessary modules for the main function:
- `std`: Zig's standard library
- `config`: Configuration handling
- `server`: Server implementation
- `logger`: Logging utilities

### Memory Management

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();
```

This creates a General Purpose Allocator (GPA) for memory management. The `defer` statement ensures that the allocator is properly cleaned up when the function exits, preventing memory leaks.

### Logger Initialization

```zig
try logger.init(allocator);
defer logger.deinit();
```

Initializes the logging system and ensures it's properly cleaned up when the program exits.

### Configuration Loading

```zig
var server_config: config.Config = undefined;
if (args.len > 1) {
    // Load configuration from file
    server_config = try config.loadFromFile(allocator, args[1]);
} else {
    // Use default configuration
    server_config = config.getDefaultConfig(allocator);
}
defer server_config.deinit();
```

This code loads the server configuration either from a file specified as a command-line argument or uses default values if no file is provided. The `defer` statement ensures that any resources allocated by the configuration are properly freed.

### Server Initialization and Startup

```zig
var proxy_server = try server.Server.init(allocator, server_config);
defer proxy_server.deinit();

try proxy_server.start();
```

Creates and starts the ZProxy server with the loaded configuration. The `defer` statement ensures that the server is properly cleaned up when the program exits.

### Signal Handling

```zig
const signal = try waitForSignal();
logger.info("Received signal: {}, shutting down...", .{signal});
```

Waits for a termination signal (currently simulated with user input) to initiate a graceful shutdown.

### Graceful Shutdown

```zig
try proxy_server.stop();
logger.info("ZProxy shutdown complete", .{});
```

Stops the server gracefully, allowing it to complete any in-progress requests before shutting down.

### Test Integration

```zig
test {
    // Run all tests in the project
    std.testing.refAllDeclsRecursive(@This());
    _ = @import("config/config.zig");
    _ = @import("server/server.zig");
    // ... other imports
}
```

This block ensures that all tests in the project are run when executing `zig build test`.

## Zig Programming Principles

1. **Error Handling**: The `try` keyword is used for functions that can return errors, automatically propagating errors up the call stack.
2. **Resource Management**: `defer` statements ensure resources are properly cleaned up, even if an error occurs.
3. **Memory Safety**: The allocator pattern ensures memory is properly managed.
4. **Testing Integration**: Tests are integrated directly into the code.

## Usage

The main function can be invoked with an optional configuration file path:

```bash
# Run with default configuration
./zproxy

# Run with a specific configuration file
./zproxy config.json
```
