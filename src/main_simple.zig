const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("ZProxy - Restructured Project\n", .{});
    try stdout.print("This is a minimal example to verify the project structure.\n", .{});
}
