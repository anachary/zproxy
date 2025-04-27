const std = @import("std");
const types = @import("types.zig");

/// Rate limiting middleware
pub const RateLimitMiddleware = struct {
    allocator: std.mem.Allocator,
    requests_per_minute: u32,
    client_limits: std.StringHashMap(ClientLimit),
    mutex: std.Thread.Mutex,

    /// Client rate limit information
    const ClientLimit = struct {
        requests: u32,
        reset_time: i64,
    };

    /// Create a new rate limit middleware
    pub fn create(allocator: std.mem.Allocator, config: anytype) !*types.Middleware {
        var middleware = try allocator.create(RateLimitMiddleware);
        middleware.* = RateLimitMiddleware{
            .allocator = allocator,
            .requests_per_minute = config.requests_per_minute,
            .client_limits = std.StringHashMap(ClientLimit).init(allocator),
            .mutex = std.Thread.Mutex{},
        };

        return @ptrCast(middleware);
    }

    /// Process a request
    pub fn process(self: *const RateLimitMiddleware, context: *types.Context) !types.Result {
        // Get client IP address
        const client_ip = try self.getClientIp(context);

        self.mutex.lock();
        defer self.mutex.unlock();

        // Clean up expired limits
        try self.cleanupExpiredLimits();

        // Check if client has a limit entry
        const now = std.time.milliTimestamp();
        var client_limit: *ClientLimit = undefined;

        if (self.client_limits.getPtr(client_ip)) |limit| {
            client_limit = limit;

            // Check if the limit period has expired
            if (now > client_limit.reset_time) {
                // Reset the limit
                client_limit.requests = 1;
                client_limit.reset_time = now + 60 * 1000; // 1 minute
            } else {
                // Increment request count
                client_limit.requests += 1;

                // Check if limit exceeded
                if (client_limit.requests > self.requests_per_minute) {
                    return types.Result{
                        .success = false,
                        .status_code = 429,
                        .error_message = "Rate limit exceeded",
                    };
                }
            }
        } else {
            // Create a new limit entry
            const client_ip_copy = try self.allocator.dupe(u8, client_ip);
            errdefer self.allocator.free(client_ip_copy);

            try self.client_limits.put(client_ip_copy, ClientLimit{
                .requests = 1,
                .reset_time = now + 60 * 1000, // 1 minute
            });
        }

        return types.Result{ .success = true };
    }

    /// Get client IP address from request
    fn getClientIp(self: *const RateLimitMiddleware, context: *types.Context) ![]const u8 {
        _ = self;
        // Try to get X-Forwarded-For header
        if (context.request.headers.get("X-Forwarded-For")) |forwarded_for| {
            // Use the first IP in the list
            var ips = std.mem.split(u8, forwarded_for, ",");
            const ip = ips.next() orelse return error.NoClientIp;
            return std.mem.trim(u8, ip, " ");
        }

        // Fall back to connection address
        return "127.0.0.1"; // Placeholder
    }

    /// Clean up expired limits
    fn cleanupExpiredLimits(self: *const RateLimitMiddleware) !void {
        const now = std.time.milliTimestamp();
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        var it = self.client_limits.iterator();
        while (it.next()) |entry| {
            if (now > entry.value_ptr.reset_time) {
                try to_remove.append(entry.key_ptr.*);
            }
        }

        for (to_remove.items) |key| {
            const removed = self.client_limits.fetchRemove(key);
            if (removed != null) {
                self.allocator.free(removed.?.key);
            }
        }
    }
};
