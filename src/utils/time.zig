const std = @import("std");

/// Get the current timestamp in milliseconds
pub fn currentTimeMillis() i64 {
    return std.time.milliTimestamp();
}

/// Get the current timestamp in seconds
pub fn currentTimeSeconds() i64 {
    return @divFloor(std.time.milliTimestamp(), 1000);
}

/// Format a timestamp as an ISO 8601 string
pub fn formatTimestamp(allocator: std.mem.Allocator, timestamp_ms: i64) ![]u8 {
    const timestamp_s = @divFloor(timestamp_ms, 1000);
    const remainder_ms = @mod(timestamp_ms, 1000);

    // Convert to broken-down time
    const epoch_seconds = @as(u64, @intCast(timestamp_s));
    var seconds = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    var day = seconds.getEpochDay();
    var time = day.getDaySeconds();

    // Format as ISO 8601
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z",
        .{
            time.year + 1900,
            time.month + 1,
            time.day,
            time.hour,
            time.min,
            time.sec,
            remainder_ms,
        },
    );
}

/// Timer for measuring elapsed time
pub const Timer = struct {
    start_time: i64,

    /// Start a new timer
    pub fn start() Timer {
        return Timer{
            .start_time = std.time.milliTimestamp(),
        };
    }

    /// Get elapsed time in milliseconds
    pub fn elapsedMillis(self: *const Timer) i64 {
        return std.time.milliTimestamp() - self.start_time;
    }

    /// Get elapsed time in seconds
    pub fn elapsedSeconds(self: *const Timer) f64 {
        return @as(f64, @floatFromInt(self.elapsedMillis())) / 1000.0;
    }

    /// Reset the timer
    pub fn reset(self: *Timer) void {
        self.start_time = std.time.milliTimestamp();
    }
};
