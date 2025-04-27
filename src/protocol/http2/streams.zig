const std = @import("std");
const frames = @import("frames.zig");
const utils = @import("../../utils/allocator.zig");

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

/// HTTP/2 stream priority
pub const StreamPriority = struct {
    exclusive: bool,
    dependency_id: u31,
    weight: u8,
};

/// HTTP/2 stream
pub const Stream = struct {
    allocator: std.mem.Allocator,
    id: u31,
    state: StreamState,
    connection: *frames.Connection,
    window_size: u32,
    priority: ?StreamPriority,
    headers: ?[]frames.Header,
    body: ?std.ArrayList(u8),
    mutex: std.Thread.Mutex,

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
            .priority = null,
            .headers = null,
            .body = null,
            .mutex = std.Thread.Mutex{},
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Stream) void {
        if (self.headers) |headers| {
            for (headers) |header| {
                self.allocator.free(header.name);
                self.allocator.free(header.value);
            }
            self.allocator.free(headers);
        }

        if (self.body) |*body| {
            body.deinit();
        }
    }

    /// Set headers for this stream
    pub fn setHeaders(self: *Stream, headers: []const frames.Header) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Free existing headers if any
        if (self.headers) |old_headers| {
            for (old_headers) |header| {
                self.allocator.free(header.name);
                self.allocator.free(header.value);
            }
            self.allocator.free(old_headers);
        }

        // Copy the headers
        var new_headers = try self.allocator.alloc(frames.Header, headers.len);
        for (headers, 0..) |header, i| {
            new_headers[i] = frames.Header{
                .name = try self.allocator.dupe(u8, header.name),
                .value = try self.allocator.dupe(u8, header.value),
            };
        }

        self.headers = new_headers;
    }

    /// Get headers for this stream
    pub fn getHeaders(self: *Stream) ?[]frames.Header {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.headers;
    }

    /// Append data to this stream's body
    pub fn appendData(self: *Stream, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.body == null) {
            self.body = std.ArrayList(u8).init(self.allocator);
        }

        try self.body.?.appendSlice(data);
    }

    /// Get body for this stream
    pub fn getBody(self: *Stream) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.body) |*body| {
            return body.items;
        }

        return null;
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
        // Check if we need to split the data into multiple frames
        const max_frame_size = self.connection.settings.max_frame_size orelse 16384;

        if (data.len <= max_frame_size) {
            // Send in a single frame
            try self.connection.sendData(self.id, data, end_stream);
        } else {
            // Split into multiple frames
            var offset: usize = 0;
            while (offset < data.len) {
                const remaining = data.len - offset;
                const chunk_size = @min(remaining, max_frame_size);
                const is_last_chunk = offset + chunk_size >= data.len;
                const chunk_end_stream = is_last_chunk and end_stream;

                try self.connection.sendData(
                    self.id,
                    data[offset .. offset + chunk_size],
                    chunk_end_stream,
                );

                offset += chunk_size;
            }
        }

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

    /// Set priority for this stream
    pub fn setPriority(self: *Stream, priority: StreamPriority) void {
        self.priority = priority;
    }
};

/// HTTP/2 stream manager
pub const StreamManager = struct {
    allocator: std.mem.Allocator,
    streams: std.AutoHashMap(u31, Stream),
    next_stream_id: u31,
    max_concurrent_streams: u32,
    mutex: std.Thread.Mutex,

    /// Initialize a new stream manager
    pub fn init(allocator: std.mem.Allocator) !StreamManager {
        return StreamManager{
            .allocator = allocator,
            .streams = std.AutoHashMap(u31, Stream).init(allocator),
            .next_stream_id = 1,
            .max_concurrent_streams = 100,
            .mutex = std.Thread.Mutex{},
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

    /// Create a new outgoing stream (client-initiated)
    pub fn createStream(self: *StreamManager, connection: *frames.Connection) !*Stream {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.streams.count() >= self.max_concurrent_streams) {
            return error.TooManyStreams;
        }

        const stream_id = self.next_stream_id;
        self.next_stream_id += 2; // Client streams are odd-numbered

        var stream = try Stream.init(self.allocator, stream_id, connection);
        try self.streams.put(stream_id, stream);

        return self.streams.getPtr(stream_id).?;
    }

    /// Create a new incoming stream (server-initiated)
    pub fn createIncomingStream(
        self: *StreamManager,
        connection: *frames.Connection,
        stream_id: u31,
    ) !*Stream {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.streams.count() >= self.max_concurrent_streams) {
            return error.TooManyStreams;
        }

        var stream = try Stream.init(self.allocator, stream_id, connection);
        try self.streams.put(stream_id, stream);

        return self.streams.getPtr(stream_id).?;
    }

    /// Get a stream by ID
    pub fn getStream(self: *StreamManager, stream_id: u31) ?*Stream {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.streams.getPtr(stream_id);
    }

    /// Close a stream
    pub fn closeStream(self: *StreamManager, stream_id: u31) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.streams.getPtr(stream_id)) |stream| {
            stream.state = .closed;
        }
    }

    /// Remove closed streams
    pub fn removeClosedStreams(self: *StreamManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

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

    /// Get active stream count
    pub fn activeStreamCount(self: *StreamManager) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        return self.streams.count();
    }
};
