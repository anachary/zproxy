const std = @import("std");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Print a message
    std.debug.print("ZProxy test program\n", .{});
    
    // Try to read the config file
    const config_file = try std.fs.cwd().openFile("config.json", .{});
    defer config_file.close();
    
    const file_size = try config_file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    defer allocator.free(buffer);
    
    const bytes_read = try config_file.readAll(buffer);
    std.debug.print("Read {d} bytes from config.json\n", .{bytes_read});
    
    // Print the config file content
    std.debug.print("Config file content:\n{s}\n", .{buffer});
    
    std.debug.print("ZProxy test completed successfully\n", .{});
}
