const std = @import("std");

/// Re-export buffer and time utilities
pub const buffer = @import("buffer.zig");
pub const time = @import("time.zig");

/// Arena allocator wrapper
pub const ArenaAllocator = struct {
    arena: std.heap.ArenaAllocator,

    /// Initialize a new arena allocator
    pub fn init(parent_allocator: std.mem.Allocator) ArenaAllocator {
        return ArenaAllocator{
            .arena = std.heap.ArenaAllocator.init(parent_allocator),
        };
    }

    /// Get the allocator
    pub fn getAllocator(self: *ArenaAllocator) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Clean up resources
    pub fn deinit(self: *ArenaAllocator) void {
        self.arena.deinit();
    }

    /// Reset the arena
    pub fn reset(self: *ArenaAllocator) void {
        self.arena.reset(.free_all);
    }
};

/// Bounded allocator that limits total memory usage
pub const BoundedAllocator = struct {
    allocator: std.mem.Allocator,
    limit: usize,
    used: std.atomic.Atomic(usize),

    /// Initialize a new bounded allocator
    pub fn init(parent_allocator: std.mem.Allocator, limit: usize) BoundedAllocator {
        return BoundedAllocator{
            .allocator = parent_allocator,
            .limit = limit,
            .used = std.atomic.Atomic(usize).init(0),
        };
    }

    /// Allocate memory
    pub fn alloc(self: *BoundedAllocator, len: usize, alignment: u29) ![]u8 {
        // Check if allocation would exceed limit
        const used = self.used.load(.Acquire);
        if (used + len > self.limit) {
            return error.OutOfMemory;
        }

        // Allocate memory
        const result = try self.allocator.alignedAlloc(u8, alignment, len);

        // Update used memory
        _ = self.used.fetchAdd(len, .Release);

        return result;
    }

    /// Free memory
    pub fn free(self: *BoundedAllocator, buf: []u8) void {
        // Update used memory
        _ = self.used.fetchSub(buf.len, .Release);

        // Free memory
        self.allocator.free(buf);
    }

    /// Get the allocator interface
    pub fn getAllocator(self: *BoundedAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    /// Resize memory
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u29, new_len: usize, ret_addr: usize) bool {
        const self: *BoundedAllocator = @ptrCast(@alignCast(ctx));

        // Check if resize would exceed limit
        if (new_len > buf.len) {
            const additional = new_len - buf.len;
            const used = self.used.load(.Acquire);
            if (used + additional > self.limit) {
                return false;
            }

            // Update used memory if resize succeeds
            if (self.allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
                _ = self.used.fetchAdd(additional, .Release);
                return true;
            }
            return false;
        } else {
            // Shrinking, update used memory if resize succeeds
            const reduction = buf.len - new_len;
            if (self.allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
                _ = self.used.fetchSub(reduction, .Release);
                return true;
            }
            return false;
        }
    }
};
