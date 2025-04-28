const std = @import("std");
const logger = @import("logger.zig");

/// NUMA node
pub const NumaNode = struct {
    id: u32,
    cpus: []u32,
    memory: u64,
    
    /// Clean up NUMA node resources
    pub fn deinit(self: *NumaNode, allocator: std.mem.Allocator) void {
        allocator.free(self.cpus);
    }
};

/// NUMA topology
pub const NumaTopology = struct {
    allocator: std.mem.Allocator,
    nodes: []NumaNode,
    
    /// Initialize NUMA topology
    pub fn init(allocator: std.mem.Allocator) !NumaTopology {
        // This is a simplified implementation that just creates a single NUMA node
        // In a real implementation, we would query the system for NUMA information
        
        var nodes = try allocator.alloc(NumaNode, 1);
        errdefer allocator.free(nodes);
        
        const cpus = try allocator.alloc(u32, 1);
        errdefer allocator.free(cpus);
        
        cpus[0] = 0;
        
        nodes[0] = NumaNode{
            .id = 0,
            .cpus = cpus,
            .memory = 0,
        };
        
        return NumaTopology{
            .allocator = allocator,
            .nodes = nodes,
        };
    }
    
    /// Clean up NUMA topology resources
    pub fn deinit(self: *NumaTopology) void {
        for (self.nodes) |*node| {
            node.deinit(self.allocator);
        }
        self.allocator.free(self.nodes);
    }
    
    /// Get the number of NUMA nodes
    pub fn getNodeCount(self: *const NumaTopology) usize {
        return self.nodes.len;
    }
    
    /// Get a NUMA node by ID
    pub fn getNode(self: *const NumaTopology, id: u32) ?*const NumaNode {
        for (self.nodes) |*node| {
            if (node.id == id) {
                return node;
            }
        }
        return null;
    }
    
    /// Get the NUMA node for a CPU
    pub fn getNodeForCpu(self: *const NumaTopology, cpu: u32) ?*const NumaNode {
        for (self.nodes) |*node| {
            for (node.cpus) |node_cpu| {
                if (node_cpu == cpu) {
                    return node;
                }
            }
        }
        return null;
    }
    
    /// Set the CPU affinity for the current thread
    pub fn setCpuAffinity(cpu: u32) !void {
        // This is a simplified implementation
        // In a real implementation, we would use platform-specific APIs
        
        logger.debug("Setting CPU affinity to {d}", .{cpu});
        
        // On Linux, we would use sched_setaffinity
        // On Windows, we would use SetThreadAffinityMask
        
        // For now, just return success
    }
    
    /// Set the NUMA node affinity for the current thread
    pub fn setNodeAffinity(self: *const NumaTopology, node_id: u32) !void {
        const node = self.getNode(node_id) orelse return error.InvalidNode;
        
        // Set CPU affinity to the first CPU in the node
        if (node.cpus.len > 0) {
            try setCpuAffinity(node.cpus[0]);
        }
    }
};

test "NUMA - Topology" {
    const testing = std.testing;
    
    // Create NUMA topology
    var topology = try NumaTopology.init(testing.allocator);
    defer topology.deinit();
    
    // Check node count
    try testing.expectEqual(@as(usize, 1), topology.getNodeCount());
    
    // Get node
    const node = topology.getNode(0) orelse return error.NodeNotFound;
    
    try testing.expectEqual(@as(u32, 0), node.id);
    try testing.expectEqual(@as(usize, 1), node.cpus.len);
    try testing.expectEqual(@as(u32, 0), node.cpus[0]);
    
    // Get node for CPU
    const node_for_cpu = topology.getNodeForCpu(0) orelse return error.NodeNotFound;
    
    try testing.expectEqual(@as(u32, 0), node_for_cpu.id);
}
