const std = @import("std");

/// Buffer pool
pub const BufferPool = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList([]u8),
    buffer_size: usize,
    mutex: std.Thread.Mutex,
    
    /// Initialize a new buffer pool
    pub fn init(allocator: std.mem.Allocator, buffer_size: usize, initial_count: usize) !BufferPool {
        var buffers = std.ArrayList([]u8).init(allocator);
        errdefer buffers.deinit();
        
        // Allocate initial buffers
        for (0..initial_count) |_| {
            const buffer = try allocator.alloc(u8, buffer_size);
            errdefer allocator.free(buffer);
            
            try buffers.append(buffer);
        }
        
        return BufferPool{
            .allocator = allocator,
            .buffers = buffers,
            .buffer_size = buffer_size,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    /// Get a buffer from the pool
    pub fn getBuffer(self: *BufferPool) ![]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.buffers.items.len == 0) {
            // Allocate a new buffer
            return self.allocator.alloc(u8, self.buffer_size);
        }
        
        // Get a buffer from the pool
        return self.buffers.pop();
    }
    
    /// Return a buffer to the pool
    pub fn returnBuffer(self: *BufferPool, buffer: []u8) void {
        if (buffer.len != self.buffer_size) {
            // Buffer is not from this pool, free it
            self.allocator.free(buffer);
            return;
        }
        
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Return buffer to the pool
        self.buffers.append(buffer) catch {
            // Failed to append, free the buffer
            self.allocator.free(buffer);
        };
    }
    
    /// Clean up buffer pool resources
    pub fn deinit(self: *BufferPool) void {
        // Free all buffers
        for (self.buffers.items) |buffer| {
            self.allocator.free(buffer);
        }
        
        // Free buffer list
        self.buffers.deinit();
    }
};

/// Growable buffer
pub const GrowableBuffer = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    len: usize,
    
    /// Initialize a new growable buffer
    pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !GrowableBuffer {
        const buffer = try allocator.alloc(u8, initial_capacity);
        
        return GrowableBuffer{
            .allocator = allocator,
            .buffer = buffer,
            .len = 0,
        };
    }
    
    /// Append data to the buffer
    pub fn append(self: *GrowableBuffer, data: []const u8) !void {
        const new_len = self.len + data.len;
        
        if (new_len > self.buffer.len) {
            // Need to grow the buffer
            const new_capacity = std.math.max(new_len, self.buffer.len * 2);
            const new_buffer = try self.allocator.realloc(self.buffer, new_capacity);
            self.buffer = new_buffer;
        }
        
        // Copy data to the buffer
        std.mem.copy(u8, self.buffer[self.len..], data);
        self.len = new_len;
    }
    
    /// Reset the buffer
    pub fn reset(self: *GrowableBuffer) void {
        self.len = 0;
    }
    
    /// Get the buffer contents
    pub fn getContents(self: *const GrowableBuffer) []const u8 {
        return self.buffer[0..self.len];
    }
    
    /// Clean up growable buffer resources
    pub fn deinit(self: *GrowableBuffer) void {
        self.allocator.free(self.buffer);
    }
};

test "Buffer - Buffer Pool" {
    const testing = std.testing;
    
    // Create a buffer pool
    var pool = try BufferPool.init(testing.allocator, 1024, 2);
    defer pool.deinit();
    
    // Get a buffer
    const buffer1 = try pool.getBuffer();
    defer pool.returnBuffer(buffer1);
    
    try testing.expectEqual(@as(usize, 1024), buffer1.len);
    
    // Get another buffer
    const buffer2 = try pool.getBuffer();
    defer pool.returnBuffer(buffer2);
    
    try testing.expectEqual(@as(usize, 1024), buffer2.len);
    
    // Get a third buffer (should allocate a new one)
    const buffer3 = try pool.getBuffer();
    defer pool.returnBuffer(buffer3);
    
    try testing.expectEqual(@as(usize, 1024), buffer3.len);
}

test "Buffer - Growable Buffer" {
    const testing = std.testing;
    
    // Create a growable buffer
    var buffer = try GrowableBuffer.init(testing.allocator, 16);
    defer buffer.deinit();
    
    // Append data
    try buffer.append("Hello, ");
    try buffer.append("world!");
    
    // Check contents
    try testing.expectEqualStrings("Hello, world!", buffer.getContents());
    
    // Reset buffer
    buffer.reset();
    
    // Append more data
    try buffer.append("Reset buffer");
    
    // Check contents
    try testing.expectEqualStrings("Reset buffer", buffer.getContents());
}
