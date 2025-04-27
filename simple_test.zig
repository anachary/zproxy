const std = @import("std");

pub fn main() !void {
    std.debug.print("ZProxy test program\n", .{});

    // Check if config.json exists
    const file_exists = blk: {
        std.fs.cwd().access("config.json", .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    std.debug.print("Config file exists: {}\n", .{file_exists});
    std.debug.print("Test completed successfully\n", .{});
}
