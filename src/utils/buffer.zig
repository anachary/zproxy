const std = @import("std");

/// Buffer pool for reusing memory buffers
pub const BufferPool = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList([]u8),
    buffer_size: usize,
    max_buffers: usize,
    mutex: std.Thread.Mutex,
    
    /// Initialize a new buffer pool
    pub fn init(allocator: std.mem.Allocator, buffer_size: usize, max_buffers: usize) BufferPool {
        return BufferPool{
            .allocator = allocator,
            .buffers = std.ArrayList([]u8).init(allocator),
            .buffer_size = buffer_size,
            .max_buffers = max_buffers,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *BufferPool) void {
        for (self.buffers.items) |buffer| {
            self.allocator.free(buffer);
        }
        self.buffers.deinit();
    }
    
    /// Get a buffer from the pool
    pub fn getBuffer(self: *BufferPool) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.buffers.items.len > 0) {
            // Reuse an existing buffer
            return self.buffers.pop();
        } else {
            // Create a new buffer
            return self.allocator.alloc(u8, self.buffer_size);
        }
    }
    
    /// Return a buffer to the pool
    pub fn returnBuffer(self: *BufferPool, buffer: []u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (buffer.len != self.buffer_size) {
            // Buffer size doesn't match, free it
            self.allocator.free(buffer);
            return;
        }
        
        if (self.buffers.items.len < self.max_buffers) {
            // Add buffer to pool
            self.buffers.append(buffer) catch {
                // Failed to add to pool, free it
                self.allocator.free(buffer);
            };
        } else {
            // Pool is full, free the buffer
            self.allocator.free(buffer);
        }
    }
};

/// Growable buffer for building strings
pub const StringBuilder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    
    /// Initialize a new string builder
    pub fn init(allocator: std.mem.Allocator) StringBuilder {
        return StringBuilder{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *StringBuilder) void {
        self.buffer.deinit();
    }
    
    /// Append a string
    pub fn append(self: *StringBuilder, str: []const u8) !void {
        try self.buffer.appendSlice(str);
    }
    
    /// Append a formatted string
    pub fn appendFmt(self: *StringBuilder, comptime fmt: []const u8, args: anytype) !void {
        try std.fmt.format(self.buffer.writer(), fmt, args);
    }
    
    /// Get the built string
    pub fn string(self: *const StringBuilder) []const u8 {
        return self.buffer.items;
    }
    
    /// Get a copy of the built string
    pub fn toOwnedString(self: *StringBuilder) ![]u8 {
        return self.buffer.toOwnedSlice();
    }
    
    /// Reset the builder
    pub fn reset(self: *StringBuilder) void {
        self.buffer.clearRetainingCapacity();
    }
};
