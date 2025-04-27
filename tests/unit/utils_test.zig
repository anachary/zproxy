const std = @import("std");
const testing = std.testing;
const utils = @import("utils");

test "Arena allocator" {
    const allocator = testing.allocator;
    
    var arena = utils.ArenaAllocator.init(allocator);
    defer arena.deinit();
    
    const arena_allocator = arena.allocator();
    
    // Allocate some memory
    const memory1 = try arena_allocator.alloc(u8, 1024);
    const memory2 = try arena_allocator.alloc(u8, 2048);
    
    try testing.expectEqual(@as(usize, 1024), memory1.len);
    try testing.expectEqual(@as(usize, 2048), memory2.len);
    
    // Reset the arena
    arena.reset();
    
    // Allocate more memory
    const memory3 = try arena_allocator.alloc(u8, 4096);
    try testing.expectEqual(@as(usize, 4096), memory3.len);
}

test "Buffer pool" {
    const allocator = testing.allocator;
    
    var pool = utils.buffer.BufferPool.init(allocator, 1024, 10);
    defer pool.deinit();
    
    // Get a buffer
    const buffer1 = try pool.getBuffer();
    try testing.expectEqual(@as(usize, 1024), buffer1.len);
    
    // Return the buffer
    pool.returnBuffer(buffer1);
    
    // Get another buffer (should reuse the first one)
    const buffer2 = try pool.getBuffer();
    try testing.expectEqual(@as(usize, 1024), buffer2.len);
    
    // Return the buffer
    pool.returnBuffer(buffer2);
}

test "String builder" {
    const allocator = testing.allocator;
    
    var builder = utils.buffer.StringBuilder.init(allocator);
    defer builder.deinit();
    
    // Append strings
    try builder.append("Hello, ");
    try builder.append("world!");
    
    // Append formatted string
    try builder.appendFmt(" The answer is {d}.", .{42});
    
    // Get the result
    const result = builder.string();
    try testing.expectEqualStrings("Hello, world! The answer is 42.", result);
    
    // Reset the builder
    builder.reset();
    try testing.expectEqualStrings("", builder.string());
}

test "Time utilities" {
    const allocator = testing.allocator;
    
    // Get current time
    const now = utils.time.currentTimeMillis();
    try testing.expect(now > 0);
    
    // Format timestamp
    const formatted = try utils.time.formatTimestamp(allocator, now);
    defer allocator.free(formatted);
    
    // Check format (YYYY-MM-DDTHH:MM:SS.MMMZ)
    try testing.expectEqual(@as(usize, 24), formatted.len);
    try testing.expect(formatted[4] == '-');
    try testing.expect(formatted[7] == '-');
    try testing.expect(formatted[10] == 'T');
    try testing.expect(formatted[13] == ':');
    try testing.expect(formatted[16] == ':');
    try testing.expect(formatted[19] == '.');
    try testing.expect(formatted[23] == 'Z');
    
    // Test timer
    var timer = utils.time.Timer.start();
    std.time.sleep(10 * std.time.ns_per_ms); // Sleep for 10ms
    const elapsed = timer.elapsedMillis();
    try testing.expect(elapsed >= 10);
    
    // Reset timer
    timer.reset();
    const elapsed_after_reset = timer.elapsedMillis();
    try testing.expect(elapsed_after_reset < elapsed);
}
