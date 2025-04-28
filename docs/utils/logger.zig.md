# logger.zig Documentation

## Overview

The `logger.zig` file implements a flexible logging system for ZProxy. It supports multiple log levels, console and file output, and thread-safe logging.

## Key Components

### Log Levels

```zig
pub const LogLevel = enum {
    debug,
    info,
    warning,
    err,
    critical,
    
    pub fn toString(self: LogLevel) []const u8 {
        // Convert log level to string
    }
    
    pub fn fromString(str: []const u8) !LogLevel {
        // Convert string to log level
    }
};
```

This enumeration defines the available log levels, from least to most severe:
- `debug`: Detailed information for debugging
- `info`: General information about system operation
- `warning`: Potential issues that don't prevent operation
- `err`: Errors that prevent specific operations
- `critical`: Critical errors that may prevent system operation

The `toString` and `fromString` methods convert between log levels and their string representations.

### Logger Configuration

```zig
pub const LoggerConfig = struct {
    level: LogLevel = .info,
    file: ?[]const u8 = null,
    
    pub fn deinit(self: *LoggerConfig, allocator: std.mem.Allocator) void {
        // Free allocated memory
    }
};
```

This structure holds logger configuration:
- `level`: The minimum log level to output
- `file`: Optional path to a log file

The `deinit` method ensures proper cleanup of allocated memory.

### Global State

```zig
var config: LoggerConfig = .{};
var file: ?std.fs.File = null;
var mutex: std.Thread.Mutex = .{};
var global_allocator: std.mem.Allocator = undefined;
```

These variables maintain the logger's global state:
- `config`: The current logger configuration
- `file`: The open log file, if any
- `mutex`: A mutex for thread-safe logging
- `global_allocator`: The allocator used for memory management

### Initialization and Cleanup

```zig
pub fn init(allocator: std.mem.Allocator) !void {
    // Initialize the logger
}

pub fn deinit() void {
    // Clean up logger resources
}
```

These functions initialize and clean up the logger:
- `init`: Stores the allocator and opens the log file if specified
- `deinit`: Closes the log file and frees allocated memory

### Configuration Methods

```zig
pub fn setLevel(level: LogLevel) void {
    // Set the log level
}

pub fn setFile(log_file: []const u8) !void {
    // Set the log file
}
```

These functions allow changing the logger configuration at runtime:
- `setLevel`: Changes the minimum log level
- `setFile`: Changes the log file

### Logging Methods

```zig
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    log(.debug, fmt, args);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    log(.info, fmt, args);
}

// ... other log level methods ...

pub fn log(level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    // Log a message at the specified level
}
```

These functions log messages at different levels:
- `debug`, `info`, `warning`, `err`, `critical`: Log at specific levels
- `log`: The core logging function that formats and outputs messages

The `log` function:
1. Checks if the message should be logged based on the current level
2. Locks the mutex for thread safety
3. Gets the current timestamp
4. Formats the log message with timestamp and level
5. Writes to stdout
6. Writes to the log file if configured

### Testing

```zig
test "Logger - Log Levels" {
    // Test log level conversion
}
```

This test ensures that log level conversion works correctly.

## Zig Programming Principles

1. **Thread Safety**: The logger uses a mutex to prevent concurrent writes from multiple threads.
2. **Compile-Time Formatting**: The `comptime` keyword is used for format strings to enable compile-time checking.
3. **Error Handling**: Functions that can fail return errors using Zig's error union type.
4. **Optional Values**: The `?` syntax is used for optional values like the log file.
5. **Resource Safety**: The code uses proper initialization and cleanup to prevent resource leaks.

## Usage Example

```zig
// Initialize the logger
try logger.init(allocator);
defer logger.deinit();

// Configure the logger
logger.setLevel(.debug);
try logger.setFile("zproxy.log");

// Log messages
logger.debug("Debug message: {}", .{value});
logger.info("Server started on port {}", .{port});
logger.warning("Connection timeout: {}", .{client_addr});
logger.err("Failed to open file: {s}", .{file_path});
logger.critical("Out of memory: {}", .{required_bytes});
```
