const std = @import("std");
const logger = @import("logger.zig");

/// Tracking allocator that logs allocations and frees
pub const TrackingAllocator = struct {
    allocator: std.mem.Allocator,
    parent_allocator: std.mem.Allocator,
    total_allocated: usize,
    total_freed: usize,

    /// Initialize a new tracking allocator
    pub fn init(parent_allocator: std.mem.Allocator) TrackingAllocator {
        return TrackingAllocator{
            .allocator = std.mem.Allocator{
                .ptr = @ptrCast(&parent_allocator),
                .vtable = &vtable,
            },
            .parent_allocator = parent_allocator,
            .total_allocated = 0,
            .total_freed = 0,
        };
    }

    /// Allocate memory
    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self = @as(*TrackingAllocator, @ptrCast(@alignCast(ctx)));

        const result = self.parent_allocator.rawAlloc(len, log2_ptr_align, ret_addr);
        if (result != null) {
            self.total_allocated += len;
            logger.debug("Allocated {d} bytes, total: {d}", .{ len, self.total_allocated });
        }

        return result;
    }

    /// Resize memory
    fn resize(ctx: *anyopaque, buf: []u8, log2_ptr_align: u8, new_len: usize, ret_addr: usize) bool {
        const self = @as(*TrackingAllocator, @ptrCast(@alignCast(ctx)));

        const result = self.parent_allocator.rawResize(buf, log2_ptr_align, new_len, ret_addr);
        if (result) {
            if (new_len > buf.len) {
                self.total_allocated += new_len - buf.len;
                logger.debug("Expanded by {d} bytes, total: {d}", .{ new_len - buf.len, self.total_allocated });
            } else {
                self.total_freed += buf.len - new_len;
                logger.debug("Shrunk by {d} bytes, total freed: {d}", .{ buf.len - new_len, self.total_freed });
            }
        }

        return result;
    }

    /// Free memory
    fn free(ctx: *anyopaque, buf: []u8, log2_ptr_align: u8, ret_addr: usize) void {
        const self = @as(*TrackingAllocator, @ptrCast(@alignCast(ctx)));

        self.parent_allocator.rawFree(buf, log2_ptr_align, ret_addr);
        self.total_freed += buf.len;
        logger.debug("Freed {d} bytes, total freed: {d}", .{ buf.len, self.total_freed });
    }

    /// Allocator vtable
    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };
};

/// Arena allocator with fixed buffer
pub const FixedBufferArena = struct {
    buffer: []u8,
    allocator: std.mem.Allocator,
    end_index: usize,

    /// Initialize a new fixed buffer arena
    pub fn init(buffer: []u8) FixedBufferArena {
        return FixedBufferArena{
            .buffer = buffer,
            .allocator = std.mem.Allocator{
                .ptr = @ptrCast(&buffer),
                .vtable = &vtable,
            },
            .end_index = 0,
        };
    }

    /// Reset the arena
    pub fn reset(self: *FixedBufferArena) void {
        self.end_index = 0;
    }

    /// Allocate memory
    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;

        const self = @as(*FixedBufferArena, @ptrCast(@alignCast(ctx)));

        const align_mask = (@as(usize, 1) << @intCast(log2_ptr_align)) - 1;
        const start_addr = @intFromPtr(self.buffer.ptr) + self.end_index;
        const aligned_addr = (start_addr + align_mask) & ~align_mask;
        const start_index = aligned_addr - @intFromPtr(self.buffer.ptr);

        const end_index = start_index + len;
        if (end_index > self.buffer.len) {
            return null;
        }

        self.end_index = end_index;
        return @ptrCast(self.buffer.ptr + start_index);
    }

    /// Resize memory
    fn resize(ctx: *anyopaque, buf: []u8, log2_ptr_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = log2_ptr_align;
        _ = ret_addr;

        const self = @as(*FixedBufferArena, @ptrCast(@alignCast(ctx)));

        // Check if this is the most recent allocation
        if (@intFromPtr(buf.ptr) + buf.len == @intFromPtr(self.buffer.ptr) + self.end_index) {
            const start_index = @intFromPtr(buf.ptr) - @intFromPtr(self.buffer.ptr);
            const end_index = start_index + new_len;

            if (end_index <= self.buffer.len) {
                self.end_index = end_index;
                return true;
            }
        }

        return false;
    }

    /// Free memory
    fn free(ctx: *anyopaque, buf: []u8, log2_ptr_align: u8, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = log2_ptr_align;
        _ = ret_addr;

        // Do nothing, memory is freed when the arena is reset
    }

    /// Allocator vtable
    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };
};

test "Allocator - Tracking Allocator" {
    const testing = std.testing;

    // Create a tracking allocator
    var tracking_allocator = TrackingAllocator.init(testing.allocator);
    const allocator = tracking_allocator.allocator;

    // Allocate memory
    const memory = try allocator.alloc(u8, 1024);
    defer allocator.free(memory);

    try testing.expectEqual(@as(usize, 1024), tracking_allocator.total_allocated);
    try testing.expectEqual(@as(usize, 0), tracking_allocator.total_freed);

    // Resize memory
    _ = try allocator.realloc(memory, 2048);

    try testing.expectEqual(@as(usize, 2048), tracking_allocator.total_allocated);
    try testing.expectEqual(@as(usize, 1024), tracking_allocator.total_freed);
}

test "Allocator - Fixed Buffer Arena" {
    const testing = std.testing;

    // Create a buffer
    var buffer: [1024]u8 = undefined;

    // Create a fixed buffer arena
    var arena = FixedBufferArena.init(&buffer);
    const allocator = arena.allocator;

    // Allocate memory
    const memory1 = try allocator.alloc(u8, 256);
    _ = memory1;
    const memory2 = try allocator.alloc(u8, 256);
    _ = memory2;

    try testing.expectEqual(@as(usize, 512), arena.end_index);

    // Reset the arena
    arena.reset();

    try testing.expectEqual(@as(usize, 0), arena.end_index);

    // Allocate memory again
    const memory3 = try allocator.alloc(u8, 512);
    _ = memory3;

    try testing.expectEqual(@as(usize, 512), arena.end_index);

    // Try to allocate too much memory
    const result = allocator.alloc(u8, 1024);
    try testing.expectError(error.OutOfMemory, result);
}
