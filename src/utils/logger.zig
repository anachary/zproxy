const std = @import("std");

/// Log levels
pub const LogLevel = enum {
    debug,
    info,
    warning,
    err,
    critical,

    /// Convert log level to string
    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warning => "WARNING",
            .err => "ERROR",
            .critical => "CRITICAL",
        };
    }

    /// Convert string to log level
    pub fn fromString(str: []const u8) !LogLevel {
        if (std.mem.eql(u8, str, "DEBUG")) {
            return .debug;
        } else if (std.mem.eql(u8, str, "INFO")) {
            return .info;
        } else if (std.mem.eql(u8, str, "WARNING")) {
            return .warning;
        } else if (std.mem.eql(u8, str, "ERROR")) {
            return .err;
        } else if (std.mem.eql(u8, str, "CRITICAL")) {
            return .critical;
        } else {
            return error.InvalidLogLevel;
        }
    }
};

/// Logger configuration
pub const LoggerConfig = struct {
    level: LogLevel = .info,
    file: ?[]const u8 = null,

    pub fn deinit(self: *LoggerConfig, allocator: std.mem.Allocator) void {
        if (self.file) |log_file| {
            allocator.free(log_file);
        }
    }
};

/// Global logger state
var config: LoggerConfig = .{};
var file: ?std.fs.File = null;
var mutex: std.Thread.Mutex = .{};
var global_allocator: std.mem.Allocator = undefined;

/// Initialize the logger
pub fn init(allocator: std.mem.Allocator) !void {
    global_allocator = allocator;

    // If a log file is specified, open it
    if (config.file) |log_file| {
        file = try std.fs.cwd().createFile(log_file, .{
            .read = true,
            .truncate = false,
        });
    }
}

/// Clean up logger resources
pub fn deinit() void {
    if (file) |f| {
        f.close();
        file = null;
    }

    if (config.file) |log_file| {
        global_allocator.free(log_file);
        config.file = null;
    }
}

/// Set the log level
pub fn setLevel(level: LogLevel) void {
    config.level = level;
}

/// Set the log file
pub fn setFile(log_file: []const u8) !void {
    // Close existing file if any
    if (file) |f| {
        f.close();
        file = null;
    }

    // Free existing file path if any
    if (config.file) |old_file| {
        global_allocator.free(old_file);
    }

    // Set new file path
    config.file = try global_allocator.dupe(u8, log_file);

    // Open new file
    file = try std.fs.cwd().createFile(log_file, .{
        .read = true,
        .truncate = false,
    });
}

/// Log a message at debug level
pub fn debug(comptime fmt: []const u8, args: anytype) void {
    log(.debug, fmt, args);
}

/// Log a message at info level
pub fn info(comptime fmt: []const u8, args: anytype) void {
    log(.info, fmt, args);
}

/// Log a message at warning level
pub fn warning(comptime fmt: []const u8, args: anytype) void {
    log(.warning, fmt, args);
}

/// Log a message at error level
pub fn err(comptime fmt: []const u8, args: anytype) void {
    log(.err, fmt, args);
}

/// Log a message at critical level
pub fn critical(comptime fmt: []const u8, args: anytype) void {
    log(.critical, fmt, args);
}

/// Log a message at the specified level
pub fn log(level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    // Skip if log level is too low
    if (@intFromEnum(level) < @intFromEnum(config.level)) {
        return;
    }

    // Lock the mutex to prevent concurrent writes
    mutex.lock();
    defer mutex.unlock();

    // Get current timestamp
    const timestamp = std.time.timestamp();

    // Get current time components using std.time.epoch
    const seconds_since_epoch = @divFloor(timestamp, std.time.ns_per_s);
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(seconds_since_epoch) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    // Extract time components
    const year = year_day.year;
    const month = @intFromEnum(month_day.month);
    const day = month_day.day_index + 1;
    const hour = @divTrunc(day_seconds, 3600);
    const minute = @divTrunc(day_seconds % 3600, 60);
    const second = day_seconds % 60;

    // Format the log message
    const stdout = std.io.getStdOut().writer();

    // Write timestamp
    stdout.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
        year,
        month,
        day,
        hour,
        minute,
        second,
    }) catch {};

    // Write log level
    stdout.print("[{s}] ", .{level.toString()}) catch {};

    // Write message
    stdout.print(fmt ++ "\n", args) catch {};

    // Write to file if configured
    if (file) |f| {
        const writer = f.writer();

        // Write timestamp
        writer.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
            year,
            month,
            day,
            hour,
            minute,
            second,
        }) catch {};

        // Write log level
        writer.print("[{s}] ", .{level.toString()}) catch {};

        // Write message
        writer.print(fmt ++ "\n", args) catch {};
    }
}

test "Logger - Log Levels" {
    const testing = std.testing;

    try testing.expectEqual(@as(usize, 5), @typeInfo(LogLevel).Enum.fields.len);
    try testing.expectEqualStrings("DEBUG", LogLevel.debug.toString());
    try testing.expectEqualStrings("INFO", LogLevel.info.toString());
    try testing.expectEqualStrings("WARNING", LogLevel.warning.toString());
    try testing.expectEqualStrings("ERROR", LogLevel.err.toString());
    try testing.expectEqualStrings("CRITICAL", LogLevel.critical.toString());

    try testing.expectEqual(LogLevel.debug, try LogLevel.fromString("DEBUG"));
    try testing.expectEqual(LogLevel.info, try LogLevel.fromString("INFO"));
    try testing.expectEqual(LogLevel.warning, try LogLevel.fromString("WARNING"));
    try testing.expectEqual(LogLevel.err, try LogLevel.fromString("ERROR"));
    try testing.expectEqual(LogLevel.critical, try LogLevel.fromString("CRITICAL"));

    try testing.expectError(error.InvalidLogLevel, LogLevel.fromString("INVALID"));
}
