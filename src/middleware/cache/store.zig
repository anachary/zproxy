const std = @import("std");

/// Cache entry
const CacheEntry = struct {
    value: []const u8,
    expires_at: i64,
};

/// Cache store for storing responses
pub const CacheStore = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    mutex: std.Thread.Mutex,
    
    /// Initialize a new cache store
    pub fn init(allocator: std.mem.Allocator) !CacheStore {
        return CacheStore{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *CacheStore) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.value);
        }
        self.entries.deinit();
    }
    
    /// Get a value from the cache
    pub fn get(self: *const CacheStore, key: []const u8) !?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clean up expired entries
        try self.cleanupExpiredEntries();
        
        // Check if key exists
        if (self.entries.get(key)) |entry| {
            // Check if entry has expired
            const now = std.time.milliTimestamp();
            if (now > entry.expires_at) {
                return null;
            }
            
            return entry.value;
        }
        
        return null;
    }
    
    /// Set a value in the cache
    pub fn set(self: *const CacheStore, key: []const u8, value: []const u8, ttl_seconds: u32) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        // Clean up expired entries
        try self.cleanupExpiredEntries();
        
        // Calculate expiration time
        const now = std.time.milliTimestamp();
        const expires_at = now + @as(i64, ttl_seconds) * 1000;
        
        // Copy key and value
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        
        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);
        
        // Remove existing entry if it exists
        if (self.entries.fetchRemove(key)) |old_entry| {
            self.allocator.free(old_entry.key);
            self.allocator.free(old_entry.value.value);
        }
        
        // Add new entry
        try self.entries.put(key_copy, CacheEntry{
            .value = value_copy,
            .expires_at = expires_at,
        });
    }
    
    /// Remove a value from the cache
    pub fn remove(self: *const CacheStore, key: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        if (self.entries.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value.value);
        }
    }
    
    /// Clean up expired entries
    fn cleanupExpiredEntries(self: *const CacheStore) !void {
        const now = std.time.milliTimestamp();
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();
        
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            if (now > entry.value_ptr.expires_at) {
                try to_remove.append(entry.key_ptr.*);
            }
        }
        
        for (to_remove.items) |key| {
            if (self.entries.fetchRemove(key)) |entry| {
                self.allocator.free(entry.key);
                self.allocator.free(entry.value.value);
            }
        }
    }
};
