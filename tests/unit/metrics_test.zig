const std = @import("std");
const testing = std.testing;
const metrics = @import("metrics");

test "Metrics collector" {
    const allocator = testing.allocator;
    
    // Create metrics collector
    var collector = try metrics.Collector.init(allocator);
    defer collector.deinit();
    
    // Test counter
    try collector.incrementCounter("test_counter", 1);
    try collector.incrementCounter("test_counter", 2);
    
    // Test gauge
    try collector.setGauge("test_gauge", 42);
    
    // Test histogram
    try collector.recordHistogram("test_histogram", 10.5);
    try collector.recordHistogram("test_histogram", 20.5);
    try collector.recordHistogram("test_histogram", 30.5);
    
    // Report metrics
    try collector.report();
    
    // We can't easily verify the metrics values in this test,
    // but we can at least verify that the operations don't fail
    try testing.expect(true);
}
