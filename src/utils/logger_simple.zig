const std = @import("std");

/// Log level
pub const LogLevel = enum {
    debug,
    info,
    warning,
    err,

    /// Convert log level to string
    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warning => "WARNING",
            .err => "ERROR",
        };
    }

    /// Convert log level to color
    pub fn toColor(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "\x1b[36m", // Cyan
            .info => "\x1b[32m", // Green
            .warning => "\x1b[33m", // Yellow
            .err => "\x1b[31m", // Red
        };
    }
};

/// Logger configuration
var log_level: LogLevel = .info;

/// Initialize the logger
pub fn init(level: LogLevel) void {
    log_level = level;
}

/// Clean up logger resources
pub fn deinit() void {
    // Nothing to clean up in this simplified version
}

/// Log a message
pub fn log(level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    if (@intFromEnum(level) < @intFromEnum(log_level)) {
        return;
    }

    // Get current time
    const timestamp = std.time.timestamp();

    // Format log message
    const reset_color = "\x1b[0m";
    const level_color = level.toColor();
    const level_str = level.toString();

    // Write to stdout
    std.debug.print("{s}[{d}] {s}{s} ", .{
        level_color,
        timestamp,
        level_str,
        reset_color,
    });
    std.debug.print(fmt ++ "\n", args);
}

/// Log a debug message
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    log(.debug, fmt, args);
}

/// Log an info message
pub fn info(comptime fmt: []const u8, args: anytype) void {
    log(.info, fmt, args);
}

/// Log a warning message
pub fn warning(comptime fmt: []const u8, args: anytype) void {
    log(.warning, fmt, args);
}

/// Log an error message
pub fn err(comptime fmt: []const u8, args: anytype) void {
    log(.err, fmt, args);
}
