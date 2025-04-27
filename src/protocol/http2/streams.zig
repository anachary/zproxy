const std = @import("std");
const frames = @import("frames.zig");

/// HTTP/2 stream state
pub const StreamState = enum {
    idle,
    reserved_local,
    reserved_remote,
    open,
    half_closed_local,
    half_closed_remote,
    closed,
};

/// HTTP/2 stream
pub const Stream = struct {
    allocator: std.mem.Allocator,
    id: u31,
    state: StreamState,
    connection: *frames.Connection,
    window_size: u32,
    
    /// Initialize a new stream
    pub fn init(
        allocator: std.mem.Allocator,
        id: u31,
        connection: *frames.Connection,
    ) !Stream {
        return Stream{
            .allocator = allocator,
            .id = id,
            .state = .open,
            .connection = connection,
            .window_size = 65535, // Default initial window size
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *Stream) void {
        _ = self;
    }
    
    /// Send headers on this stream
    pub fn sendHeaders(self: *Stream, headers: []const frames.Header, end_stream: bool) !void {
        try self.connection.sendHeaders(self.id, headers, end_stream);
        
        if (end_stream) {
            self.state = switch (self.state) {
                .open => .half_closed_local,
                .half_closed_remote => .closed,
                else => self.state,
            };
        }
    }
    
    /// Send data on this stream
    pub fn sendData(self: *Stream, data: []const u8, end_stream: bool) !void {
        try self.connection.sendData(self.id, data, end_stream);
        
        if (end_stream) {
            self.state = switch (self.state) {
                .open => .half_closed_local,
                .half_closed_remote => .closed,
                else => self.state,
            };
        }
    }
    
    /// Reset this stream with an error code
    pub fn resetStream(self: *Stream, error_code: frames.ErrorCode) !void {
        try self.connection.sendRstStream(self.id, error_code);
        self.state = .closed;
    }
    
    /// Update the stream state based on received frame
    pub fn updateState(self: *Stream, frame: frames.Frame) void {
        const end_stream = (frame.header.flags & frames.FrameFlags.END_STREAM) != 0;
        
        if (end_stream) {
            self.state = switch (self.state) {
                .open => .half_closed_remote,
                .half_closed_local => .closed,
                else => self.state,
            };
        }
        
        if (frame.header.type == .RST_STREAM) {
            self.state = .closed;
        }
    }
};

/// HTTP/2 stream manager
pub const StreamManager = struct {
    allocator: std.mem.Allocator,
    streams: std.AutoHashMap(u31, Stream),
    next_stream_id: u31,
    max_concurrent_streams: u32,
    
    /// Initialize a new stream manager
    pub fn init(allocator: std.mem.Allocator) !StreamManager {
        return StreamManager{
            .allocator = allocator,
            .streams = std.AutoHashMap(u31, Stream).init(allocator),
            .next_stream_id = 1,
            .max_concurrent_streams = 100,
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *StreamManager) void {
        var it = self.streams.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.streams.deinit();
    }
    
    /// Create a new stream
    pub fn createStream(self: *StreamManager, connection: *frames.Connection) !*Stream {
        if (self.streams.count() >= self.max_concurrent_streams) {
            return error.TooManyStreams;
        }
        
        const stream_id = self.next_stream_id;
        self.next_stream_id += 2; // Client streams are odd-numbered
        
        var stream = try Stream.init(self.allocator, stream_id, connection);
        try self.streams.put(stream_id, stream);
        
        return self.streams.getPtr(stream_id).?;
    }
    
    /// Get a stream by ID
    pub fn getStream(self: *StreamManager, stream_id: u31) ?*Stream {
        return self.streams.getPtr(stream_id);
    }
    
    /// Close a stream
    pub fn closeStream(self: *StreamManager, stream_id: u31) void {
        if (self.streams.getPtr(stream_id)) |stream| {
            stream.state = .closed;
        }
    }
    
    /// Remove closed streams
    pub fn removeClosedStreams(self: *StreamManager) void {
        var it = self.streams.iterator();
        var to_remove = std.ArrayList(u31).init(self.allocator);
        defer to_remove.deinit();
        
        while (it.next()) |entry| {
            if (entry.value_ptr.state == .closed) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }
        
        for (to_remove.items) |stream_id| {
            if (self.streams.fetchRemove(stream_id)) |kv| {
                kv.value.deinit();
            }
        }
    }
};
