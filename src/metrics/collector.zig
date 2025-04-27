const std = @import("std");
const reporter = @import("reporter.zig");

/// Metrics collector
pub const Collector = struct {
    allocator: std.mem.Allocator,
    counters: std.StringHashMap(u64),
    gauges: std.StringHashMap(i64),
    histograms: std.StringHashMap(Histogram),
    reporter: reporter.Reporter,
    mutex: std.Thread.Mutex,
    
    /// Histogram for tracking distributions
    const Histogram = struct {
        buckets: std.AutoHashMap(i64, u64),
        sum: f64,
        count: u64,
    };
    
    /// Initialize a new metrics collector
    pub fn init(allocator: std.mem.Allocator) !Collector {
        return Collector{
            .allocator = allocator,
            .counters = std.StringHashMap(u64).init(allocator),
            .gauges = std.StringHashMap(i64).init(allocator),
            .histograms = std.StringHashMap(Histogram).init(allocator),
            .reporter = try reporter.Reporter.init(allocator),
            .mutex = std.Thread.Mutex{},
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *Collector) void {
        var counter_it = self.counters.iterator();
        while (counter_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.counters.deinit();
        
        var gauge_it = self.gauges.iterator();
        while (gauge_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.gauges.deinit();
        
        var histogram_it = self.histograms.iterator();
        while (histogram_it.next()) |entry| {
            entry.value_ptr.buckets.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.histograms.deinit();
        
        self.reporter.deinit();
    }
    
    /// Increment a counter
    pub fn incrementCounter(self: *Collector, name: []const u8, value: u64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);
        
        const gop = try self.counters.getOrPut(key);
        if (gop.found_existing) {
            self.allocator.free(key);
            gop.value_ptr.* += value;
        } else {
            gop.value_ptr.* = value;
        }
    }
    
    /// Set a gauge
    pub fn setGauge(self: *Collector, name: []const u8, value: i64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);
        
        const gop = try self.gauges.getOrPut(key);
        if (gop.found_existing) {
            self.allocator.free(key);
        }
        
        gop.value_ptr.* = value;
    }
    
    /// Record a histogram value
    pub fn recordHistogram(self: *Collector, name: []const u8, value: f64) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        const key = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(key);
        
        const gop = try self.histograms.getOrPut(key);
        if (!gop.found_existing) {
            gop.value_ptr.* = Histogram{
                .buckets = std.AutoHashMap(i64, u64).init(self.allocator),
                .sum = 0,
                .count = 0,
            };
        } else {
            self.allocator.free(key);
        }
        
        // Update histogram
        const bucket = @as(i64, @intFromFloat(value));
        const bucket_gop = try gop.value_ptr.buckets.getOrPut(bucket);
        if (bucket_gop.found_existing) {
            bucket_gop.value_ptr.* += 1;
        } else {
            bucket_gop.value_ptr.* = 1;
        }
        
        gop.value_ptr.sum += value;
        gop.value_ptr.count += 1;
    }
    
    /// Report metrics
    pub fn report(self: *Collector) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        
        try self.reporter.reportMetrics(
            self.counters,
            self.gauges,
            self.histograms,
        );
    }
};
