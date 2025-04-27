const std = @import("std");

/// Zero-copy buffer for efficient data transfer
pub const ZeroCopyBuffer = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    read_pos: usize,
    write_pos: usize,
    capacity: usize,
    
    /// Initialize a new zero-copy buffer
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ZeroCopyBuffer {
        const buffer = try allocator.alloc(u8, capacity);
        return ZeroCopyBuffer{
            .allocator = allocator,
            .buffer = buffer,
            .read_pos = 0,
            .write_pos = 0,
            .capacity = capacity,
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *ZeroCopyBuffer) void {
        self.allocator.free(self.buffer);
    }
    
    /// Reset the buffer
    pub fn reset(self: *ZeroCopyBuffer) void {
        self.read_pos = 0;
        self.write_pos = 0;
    }
    
    /// Get the number of bytes available to read
    pub fn readableBytes(self: *const ZeroCopyBuffer) usize {
        return self.write_pos - self.read_pos;
    }
    
    /// Get the number of bytes available to write
    pub fn writableBytes(self: *const ZeroCopyBuffer) usize {
        return self.capacity - self.write_pos;
    }
    
    /// Get a slice of readable data
    pub fn readableSlice(self: *const ZeroCopyBuffer) []const u8 {
        return self.buffer[self.read_pos..self.write_pos];
    }
    
    /// Get a slice of writable data
    pub fn writableSlice(self: *const ZeroCopyBuffer) []u8 {
        return self.buffer[self.write_pos..self.capacity];
    }
    
    /// Mark bytes as read
    pub fn markRead(self: *ZeroCopyBuffer, bytes: usize) void {
        const new_read_pos = self.read_pos + bytes;
        std.debug.assert(new_read_pos <= self.write_pos);
        self.read_pos = new_read_pos;
        
        // Compact the buffer if we've read everything
        if (self.read_pos == self.write_pos) {
            self.read_pos = 0;
            self.write_pos = 0;
        }
    }
    
    /// Mark bytes as written
    pub fn markWritten(self: *ZeroCopyBuffer, bytes: usize) void {
        const new_write_pos = self.write_pos + bytes;
        std.debug.assert(new_write_pos <= self.capacity);
        self.write_pos = new_write_pos;
    }
    
    /// Compact the buffer by moving unread data to the beginning
    pub fn compact(self: *ZeroCopyBuffer) void {
        if (self.read_pos == 0) {
            return;
        }
        
        const readable = self.readableBytes();
        if (readable > 0) {
            std.mem.copyForwards(u8, self.buffer[0..readable], self.buffer[self.read_pos..self.write_pos]);
        }
        
        self.read_pos = 0;
        self.write_pos = readable;
    }
    
    /// Read data from a stream into the buffer
    pub fn readFromStream(self: *ZeroCopyBuffer, stream: std.net.Stream) !usize {
        // Compact the buffer if needed
        if (self.writableBytes() < self.capacity / 4) {
            self.compact();
        }
        
        // Read data into the writable portion of the buffer
        const bytes_read = try stream.read(self.writableSlice());
        self.markWritten(bytes_read);
        return bytes_read;
    }
    
    /// Write data from the buffer to a stream
    pub fn writeToStream(self: *ZeroCopyBuffer, stream: std.net.Stream) !usize {
        const readable = self.readableBytes();
        if (readable == 0) {
            return 0;
        }
        
        // Write data from the readable portion of the buffer
        const bytes_written = try stream.write(self.readableSlice());
        self.markRead(bytes_written);
        return bytes_written;
    }
    
    /// Forward data from one stream to another using the buffer
    pub fn forward(self: *ZeroCopyBuffer, from: std.net.Stream, to: std.net.Stream) !usize {
        // Read data from the source stream
        const bytes_read = try self.readFromStream(from);
        if (bytes_read == 0) {
            return 0;
        }
        
        // Write data to the destination stream
        const bytes_written = try self.writeToStream(to);
        return bytes_written;
    }
    
    /// Forward all available data from one stream to another
    pub fn forwardAll(self: *ZeroCopyBuffer, from: std.net.Stream, to: std.net.Stream) !usize {
        var total_bytes: usize = 0;
        
        while (true) {
            const bytes_read = try self.readFromStream(from);
            if (bytes_read == 0) {
                break;
            }
            
            var bytes_remaining = self.readableBytes();
            while (bytes_remaining > 0) {
                const bytes_written = try self.writeToStream(to);
                if (bytes_written == 0) {
                    return total_bytes;
                }
                
                total_bytes += bytes_written;
                bytes_remaining = self.readableBytes();
            }
        }
        
        return total_bytes;
    }
};

/// Zero-copy buffer pool for efficient memory reuse
pub const ZeroCopyBufferPool = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(*ZeroCopyBuffer),
    buffer_size: usize,
    max_buffers: usize,
    mutex: std.Thread.Mutex,
    
    /// Initialize a new buffer pool
    pub fn init(allocator: std.mem.Allocator, buffer_size: usize, max_buffers: usize) ZeroCopyBufferPool {
        return ZeroCopyBufferPool{
            .allocator = allocator,
            .buffers = std.ArrayList(*ZeroCopyBuffer).init(allocator),
            .buffer_size = buffer_size,
            .max_buffers = max_buffers,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *ZeroCopyBufferPool) void {
        for (self.buffers.items) |buffer| {
            buffer.deinit();
            self.allocator.destroy(buffer);
        }
        self.buffers.deinit();
    }
    
    /// Get a buffer from the pool
    pub fn getBuffer(self: *ZeroCopyBufferPool) !*ZeroCopyBuffer {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.buffers.items.len > 0) {
            // Reuse an existing buffer
            return self.buffers.pop();
        } else {
            // Create a new buffer
            var buffer = try self.allocator.create(ZeroCopyBuffer);
            buffer.* = try ZeroCopyBuffer.init(self.allocator, self.buffer_size);
            return buffer;
        }
    }
    
    /// Return a buffer to the pool
    pub fn returnBuffer(self: *ZeroCopyBufferPool, buffer: *ZeroCopyBuffer) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Reset the buffer
        buffer.reset();
        
        if (self.buffers.items.len < self.max_buffers) {
            // Add buffer to pool
            self.buffers.append(buffer) catch {
                // Failed to add to pool, free it
                buffer.deinit();
                self.allocator.destroy(buffer);
            };
        } else {
            // Pool is full, free the buffer
            buffer.deinit();
            self.allocator.destroy(buffer);
        }
    }
};
