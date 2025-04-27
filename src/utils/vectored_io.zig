const std = @import("std");

/// Vectored I/O buffer for efficient I/O operations
pub const VectoredBuffer = struct {
    allocator: std.mem.Allocator,
    iovecs: []std.os.iovec,
    buffers: [][]u8,
    count: usize,
    capacity: usize,
    
    /// Initialize a new vectored buffer
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !VectoredBuffer {
        var iovecs = try allocator.alloc(std.os.iovec, capacity);
        errdefer allocator.free(iovecs);
        
        var buffers = try allocator.alloc([]u8, capacity);
        errdefer allocator.free(buffers);
        
        return VectoredBuffer{
            .allocator = allocator,
            .iovecs = iovecs,
            .buffers = buffers,
            .count = 0,
            .capacity = capacity,
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *VectoredBuffer) void {
        // Free all buffers
        for (self.buffers[0..self.count]) |buffer| {
            self.allocator.free(buffer);
        }
        
        // Free arrays
        self.allocator.free(self.iovecs);
        self.allocator.free(self.buffers);
    }
    
    /// Reset the buffer
    pub fn reset(self: *VectoredBuffer) void {
        // Free all buffers
        for (self.buffers[0..self.count]) |buffer| {
            self.allocator.free(buffer);
        }
        
        self.count = 0;
    }
    
    /// Add a buffer to the vectored buffer
    pub fn addBuffer(self: *VectoredBuffer, buffer: []const u8) !void {
        if (self.count >= self.capacity) {
            return error.BufferFull;
        }
        
        // Copy the buffer
        var new_buffer = try self.allocator.alloc(u8, buffer.len);
        @memcpy(new_buffer, buffer);
        
        // Add to the arrays
        self.buffers[self.count] = new_buffer;
        self.iovecs[self.count] = .{
            .iov_base = new_buffer.ptr,
            .iov_len = new_buffer.len,
        };
        
        self.count += 1;
    }
    
    /// Add a buffer without copying (takes ownership)
    pub fn addOwnedBuffer(self: *VectoredBuffer, buffer: []u8) !void {
        if (self.count >= self.capacity) {
            return error.BufferFull;
        }
        
        // Add to the arrays
        self.buffers[self.count] = buffer;
        self.iovecs[self.count] = .{
            .iov_base = buffer.ptr,
            .iov_len = buffer.len,
        };
        
        self.count += 1;
    }
    
    /// Get the total size of all buffers
    pub fn totalSize(self: *const VectoredBuffer) usize {
        var total: usize = 0;
        for (self.buffers[0..self.count]) |buffer| {
            total += buffer.len;
        }
        return total;
    }
    
    /// Write all buffers to a stream using writev
    pub fn writeToStream(self: *const VectoredBuffer, stream: std.net.Stream) !usize {
        if (self.count == 0) {
            return 0;
        }
        
        if (comptime std.Target.current.os.tag == .windows) {
            // Windows doesn't have writev, so we need to write each buffer separately
            var total_written: usize = 0;
            for (self.buffers[0..self.count]) |buffer| {
                const written = try stream.write(buffer);
                total_written += written;
                if (written < buffer.len) {
                    // Partial write, stop here
                    break;
                }
            }
            return total_written;
        } else {
            // Use writev on platforms that support it
            const fd = stream.handle;
            const written = try std.os.writev(fd, self.iovecs[0..self.count]);
            return @intCast(written);
        }
    }
    
    /// Read from a stream into a new buffer and add it to the vectored buffer
    pub fn readFromStream(self: *VectoredBuffer, stream: std.net.Stream, size: usize) !usize {
        if (self.count >= self.capacity) {
            return error.BufferFull;
        }
        
        // Allocate a new buffer
        var buffer = try self.allocator.alloc(u8, size);
        errdefer self.allocator.free(buffer);
        
        // Read into the buffer
        const read_size = try stream.read(buffer);
        
        if (read_size == 0) {
            // No data read, free the buffer
            self.allocator.free(buffer);
            return 0;
        }
        
        // Resize the buffer to the actual read size
        if (read_size < size) {
            buffer = self.allocator.realloc(buffer, read_size) catch buffer[0..read_size];
        }
        
        // Add to the arrays
        self.buffers[self.count] = buffer;
        self.iovecs[self.count] = .{
            .iov_base = buffer.ptr,
            .iov_len = buffer.len,
        };
        
        self.count += 1;
        return read_size;
    }
    
    /// Read from a stream using readv
    pub fn readvFromStream(self: *VectoredBuffer, stream: std.net.Stream) !usize {
        if (self.count >= self.capacity) {
            return error.BufferFull;
        }
        
        if (comptime std.Target.current.os.tag == .windows) {
            // Windows doesn't have readv, so we need to read into a single buffer
            var buffer = try self.allocator.alloc(u8, 65536);
            errdefer self.allocator.free(buffer);
            
            const read_size = try stream.read(buffer);
            
            if (read_size == 0) {
                // No data read, free the buffer
                self.allocator.free(buffer);
                return 0;
            }
            
            // Resize the buffer to the actual read size
            if (read_size < buffer.len) {
                buffer = self.allocator.realloc(buffer, read_size) catch buffer[0..read_size];
            }
            
            // Add to the arrays
            self.buffers[self.count] = buffer;
            self.iovecs[self.count] = .{
                .iov_base = buffer.ptr,
                .iov_len = buffer.len,
            };
            
            self.count += 1;
            return read_size;
        } else {
            // Prepare buffers for readv
            var read_buffers = try self.allocator.alloc([]u8, 16);
            defer self.allocator.free(read_buffers);
            
            var read_iovecs = try self.allocator.alloc(std.os.iovec, 16);
            defer self.allocator.free(read_iovecs);
            
            // Allocate buffers for reading
            for (0..16) |i| {
                read_buffers[i] = try self.allocator.alloc(u8, 4096);
                read_iovecs[i] = .{
                    .iov_base = read_buffers[i].ptr,
                    .iov_len = read_buffers[i].len,
                };
            }
            
            // Use readv
            const fd = stream.handle;
            const read_size = try std.os.readv(fd, read_iovecs);
            
            if (read_size == 0) {
                // No data read, free all buffers
                for (read_buffers) |buffer| {
                    self.allocator.free(buffer);
                }
                return 0;
            }
            
            // Add buffers that contain data
            var remaining = @as(usize, @intCast(read_size));
            var total_added: usize = 0;
            
            for (read_buffers, 0..) |buffer, i| {
                if (remaining == 0) {
                    // No more data, free the remaining buffers
                    for (read_buffers[i..]) |remaining_buffer| {
                        self.allocator.free(remaining_buffer);
                    }
                    break;
                }
                
                const buffer_size = @min(remaining, buffer.len);
                remaining -= buffer_size;
                
                // Resize the buffer to the actual read size
                var resized_buffer = if (buffer_size < buffer.len)
                    self.allocator.realloc(buffer, buffer_size) catch buffer[0..buffer_size]
                else
                    buffer;
                
                // Add to the arrays
                self.buffers[self.count] = resized_buffer;
                self.iovecs[self.count] = .{
                    .iov_base = resized_buffer.ptr,
                    .iov_len = resized_buffer.len,
                };
                
                self.count += 1;
                total_added += buffer_size;
                
                if (self.count >= self.capacity) {
                    // Buffer is full, free the remaining buffers
                    for (read_buffers[i+1..]) |remaining_buffer| {
                        self.allocator.free(remaining_buffer);
                    }
                    break;
                }
            }
            
            return total_added;
        }
    }
    
    /// Forward data from one stream to another using vectored I/O
    pub fn forward(self: *VectoredBuffer, from: std.net.Stream, to: std.net.Stream) !usize {
        // Read data
        const read_size = try self.readvFromStream(from);
        if (read_size == 0) {
            return 0;
        }
        
        // Write data
        const written = try self.writeToStream(to);
        
        // Reset for next use
        self.reset();
        
        return written;
    }
    
    /// Forward all available data from one stream to another
    pub fn forwardAll(self: *VectoredBuffer, from: std.net.Stream, to: std.net.Stream) !usize {
        var total_bytes: usize = 0;
        
        while (true) {
            const bytes = try self.forward(from, to);
            if (bytes == 0) {
                break;
            }
            
            total_bytes += bytes;
        }
        
        return total_bytes;
    }
};

/// Vectored I/O buffer pool for efficient memory reuse
pub const VectoredBufferPool = struct {
    allocator: std.mem.Allocator,
    buffers: std.ArrayList(*VectoredBuffer),
    buffer_capacity: usize,
    max_buffers: usize,
    mutex: std.Thread.Mutex,
    
    /// Initialize a new buffer pool
    pub fn init(allocator: std.mem.Allocator, buffer_capacity: usize, max_buffers: usize) VectoredBufferPool {
        return VectoredBufferPool{
            .allocator = allocator,
            .buffers = std.ArrayList(*VectoredBuffer).init(allocator),
            .buffer_capacity = buffer_capacity,
            .max_buffers = max_buffers,
            .mutex = std.Thread.Mutex{},
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *VectoredBufferPool) void {
        for (self.buffers.items) |buffer| {
            buffer.deinit();
            self.allocator.destroy(buffer);
        }
        self.buffers.deinit();
    }
    
    /// Get a buffer from the pool
    pub fn getBuffer(self: *VectoredBufferPool) !*VectoredBuffer {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.buffers.items.len > 0) {
            // Reuse an existing buffer
            return self.buffers.pop();
        } else {
            // Create a new buffer
            var buffer = try self.allocator.create(VectoredBuffer);
            buffer.* = try VectoredBuffer.init(self.allocator, self.buffer_capacity);
            return buffer;
        }
    }
    
    /// Return a buffer to the pool
    pub fn returnBuffer(self: *VectoredBufferPool, buffer: *VectoredBuffer) void {
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
