const std = @import("std");

/// NUMA (Non-Uniform Memory Access) utilities
pub const Numa = struct {
    /// Get the number of NUMA nodes in the system
    pub fn getNumaNodeCount() !usize {
        // On Windows, we need to use GetNumaHighestNodeNumber
        if (comptime std.Target.current.os.tag == .windows) {
            return getNumaNodeCountWindows();
        } else if (comptime std.Target.current.os.tag == .linux) {
            return getNumaNodeCountLinux();
        } else {
            // Default to 1 for unsupported platforms
            return 1;
        }
    }

    /// Get the NUMA node for a specific CPU
    pub fn getNumaNodeForCpu(cpu_id: usize) !usize {
        if (comptime std.Target.current.os.tag == .windows) {
            return getNumaNodeForCpuWindows(cpu_id);
        } else if (comptime std.Target.current.os.tag == .linux) {
            return getNumaNodeForCpuLinux(cpu_id);
        } else {
            // Default to 0 for unsupported platforms
            return 0;
        }
    }

    /// Get the CPUs for a specific NUMA node
    pub fn getCpusForNumaNode(node: usize, allocator: std.mem.Allocator) ![]usize {
        if (comptime std.Target.current.os.tag == .windows) {
            return getCpusForNumaNodeWindows(node, allocator);
        } else if (comptime std.Target.current.os.tag == .linux) {
            return getCpusForNumaNodeLinux(node, allocator);
        } else {
            // Default to all CPUs for unsupported platforms
            const cpu_count = try std.Thread.getCpuCount();
            var cpus = try allocator.alloc(usize, cpu_count);
            for (0..cpu_count) |i| {
                cpus[i] = i;
            }
            return cpus;
        }
    }

    /// Set CPU affinity for the current thread
    pub fn setThreadAffinity(cpu_id: usize) !void {
        if (comptime std.Target.current.os.tag == .windows) {
            return setThreadAffinityWindows(cpu_id);
        } else if (comptime std.Target.current.os.tag == .linux) {
            return setThreadAffinityLinux(cpu_id);
        } else {
            // No-op for unsupported platforms
            return;
        }
    }

    /// Allocate memory on a specific NUMA node
    pub fn allocOnNode(node: usize, size: usize) ![]u8 {
        if (comptime std.Target.current.os.tag == .windows) {
            return allocOnNodeWindows(node, size);
        } else if (comptime std.Target.current.os.tag == .linux) {
            return allocOnNodeLinux(node, size);
        } else {
            // Fall back to regular allocation for unsupported platforms
            return std.heap.page_allocator.alloc(u8, size);
        }
    }

    /// Free memory allocated with allocOnNode
    pub fn freeOnNode(node: usize, memory: []u8) void {
        if (comptime std.Target.current.os.tag == .windows) {
            return freeOnNodeWindows(node, memory);
        } else if (comptime std.Target.current.os.tag == .linux) {
            return freeOnNodeLinux(node, memory);
        } else {
            // Fall back to regular free for unsupported platforms
            std.heap.page_allocator.free(memory);
        }
    }

    // Windows-specific implementations
    fn getNumaNodeCountWindows() !usize {
        if (comptime std.Target.current.os.tag != .windows) {
            @compileError("Windows-specific function called on non-Windows platform");
        }

        const windows = std.os.windows;
        var highest_node: windows.ULONG = undefined;
        const result = windows.kernel32.GetNumaHighestNodeNumber(&highest_node);
        if (result == windows.FALSE) {
            return error.GetNumaHighestNodeNumberFailed;
        }
        // Add 1 because highest node is zero-based
        return @as(usize, highest_node) + 1;
    }

    fn getNumaNodeForCpuWindows(cpu_id: usize) !usize {
        if (comptime std.Target.current.os.tag != .windows) {
            @compileError("Windows-specific function called on non-Windows platform");
        }

        const windows = std.os.windows;
        var node: windows.UCHAR = undefined;
        const result = windows.kernel32.GetNumaProcessorNode(@intCast(cpu_id), &node);
        if (result == windows.FALSE) {
            return error.GetNumaProcessorNodeFailed;
        }
        return @as(usize, node);
    }

    fn getCpusForNumaNodeWindows(node: usize, allocator: std.mem.Allocator) ![]usize {
        if (comptime std.Target.current.os.tag != .windows) {
            @compileError("Windows-specific function called on non-Windows platform");
        }

        const windows = std.os.windows;
        var cpu_count: windows.ULONG = 0;
        
        // First call to get the count
        _ = windows.kernel32.GetNumaNodeProcessorMask(@intCast(node), null, &cpu_count);
        
        // Allocate buffer for processor mask
        var processor_mask = try allocator.alloc(windows.ULONG_PTR, cpu_count);
        defer allocator.free(processor_mask);
        
        // Second call to get the actual mask
        const result = windows.kernel32.GetNumaNodeProcessorMask(
            @intCast(node),
            processor_mask.ptr,
            &cpu_count
        );
        
        if (result == windows.FALSE) {
            return error.GetNumaNodeProcessorMaskFailed;
        }
        
        // Count set bits in the mask
        var cpu_list = std.ArrayList(usize).init(allocator);
        defer cpu_list.deinit();
        
        for (processor_mask, 0..) |mask, i| {
            var bit_pos: usize = 0;
            var mask_copy = mask;
            
            while (mask_copy != 0) {
                if (mask_copy & 1 != 0) {
                    try cpu_list.append(i * @bitSizeOf(windows.ULONG_PTR) + bit_pos);
                }
                mask_copy >>= 1;
                bit_pos += 1;
            }
        }
        
        return cpu_list.toOwnedSlice();
    }

    fn setThreadAffinityWindows(cpu_id: usize) !void {
        if (comptime std.Target.current.os.tag != .windows) {
            @compileError("Windows-specific function called on non-Windows platform");
        }

        const windows = std.os.windows;
        const mask: windows.DWORD_PTR = @as(windows.DWORD_PTR, 1) << @intCast(cpu_id);
        const result = windows.kernel32.SetThreadAffinityMask(
            windows.kernel32.GetCurrentThread(),
            mask
        );
        
        if (result == 0) {
            return error.SetThreadAffinityMaskFailed;
        }
    }

    fn allocOnNodeWindows(node: usize, size: usize) ![]u8 {
        if (comptime std.Target.current.os.tag != .windows) {
            @compileError("Windows-specific function called on non-Windows platform");
        }

        const windows = std.os.windows;
        const ptr = windows.kernel32.VirtualAllocExNuma(
            windows.kernel32.GetCurrentProcess(),
            null,
            size,
            windows.VIRTUAL_ALLOCATION_TYPE.COMMIT | windows.VIRTUAL_ALLOCATION_TYPE.RESERVE,
            windows.PAGE_PROTECTION_FLAGS.READWRITE,
            @intCast(node)
        );
        
        if (ptr == null) {
            return error.VirtualAllocExNumaFailed;
        }
        
        return @as([*]u8, @ptrCast(ptr))[0..size];
    }

    fn freeOnNodeWindows(node: usize, memory: []u8) void {
        _ = node;
        if (comptime std.Target.current.os.tag != .windows) {
            @compileError("Windows-specific function called on non-Windows platform");
        }

        const windows = std.os.windows;
        _ = windows.kernel32.VirtualFree(memory.ptr, 0, windows.VIRTUAL_FREE_TYPE.RELEASE);
    }

    // Linux-specific implementations
    fn getNumaNodeCountLinux() !usize {
        if (comptime std.Target.current.os.tag != .linux) {
            @compileError("Linux-specific function called on non-Linux platform");
        }

        // Try to read from /sys/devices/system/node/
        var dir = std.fs.openDirAbsolute("/sys/devices/system/node", .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound or err == error.NotDir) {
                // NUMA not supported, assume single node
                return 1;
            }
            return err;
        };
        defer dir.close();

        var count: usize = 0;
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (std.mem.startsWith(u8, entry.name, "node")) {
                count += 1;
            }
        }

        return if (count > 0) count else 1;
    }

    fn getNumaNodeForCpuLinux(cpu_id: usize) !usize {
        if (comptime std.Target.current.os.tag != .linux) {
            @compileError("Linux-specific function called on non-Linux platform");
        }

        // Read from /sys/devices/system/cpu/cpu{N}/topology/physical_package_id
        var path_buf: [128]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &path_buf,
            "/sys/devices/system/cpu/cpu{d}/node{d}",
            .{ cpu_id, 0 }
        );

        // Try each node until we find one that exists
        var node: usize = 0;
        const max_nodes = 128; // Arbitrary limit
        while (node < max_nodes) : (node += 1) {
            path_buf[path.len - 1] = @intCast('0' + @as(u8, @truncate(node)));
            const file = std.fs.openFileAbsolute(path_buf[0..path.len], .{}) catch |err| {
                if (err == error.FileNotFound) continue;
                return err;
            };
            file.close();
            return node;
        }

        // Default to node 0 if we can't determine
        return 0;
    }

    fn getCpusForNumaNodeLinux(node: usize, allocator: std.mem.Allocator) ![]usize {
        if (comptime std.Target.current.os.tag != .linux) {
            @compileError("Linux-specific function called on non-Linux platform");
        }

        // Read from /sys/devices/system/node/node{N}/cpulist
        var path_buf: [128]u8 = undefined;
        const path = try std.fmt.bufPrint(
            &path_buf,
            "/sys/devices/system/node/node{d}/cpulist",
            .{node}
        );

        const file = std.fs.openFileAbsolute(path_buf[0..path.len], .{}) catch |err| {
            if (err == error.FileNotFound) {
                // If file doesn't exist, assume all CPUs
                const cpu_count = try std.Thread.getCpuCount();
                var cpus = try allocator.alloc(usize, cpu_count);
                for (0..cpu_count) |i| {
                    cpus[i] = i;
                }
                return cpus;
            }
            return err;
        };
        defer file.close();

        // Read the CPU list (format like "0-3,5,7-9")
        const content = try file.readToEndAlloc(allocator, 1024);
        defer allocator.free(content);

        // Parse the CPU list
        var cpu_list = std.ArrayList(usize).init(allocator);
        defer cpu_list.deinit();

        var it = std.mem.tokenizeScalar(u8, content, ',');
        while (it.next()) |range| {
            if (std.mem.indexOfScalar(u8, range, '-')) |dash_idx| {
                // Range like "0-3"
                const start = try std.fmt.parseInt(usize, range[0..dash_idx], 10);
                const end = try std.fmt.parseInt(usize, range[dash_idx+1..], 10);
                var i = start;
                while (i <= end) : (i += 1) {
                    try cpu_list.append(i);
                }
            } else {
                // Single CPU like "5"
                const cpu = try std.fmt.parseInt(usize, range, 10);
                try cpu_list.append(cpu);
            }
        }

        return cpu_list.toOwnedSlice();
    }

    fn setThreadAffinityLinux(cpu_id: usize) !void {
        if (comptime std.Target.current.os.tag != .linux) {
            @compileError("Linux-specific function called on non-Linux platform");
        }

        const linux = std.os.linux;
        
        // Create CPU set with only the specified CPU
        var cpu_set: linux.cpu_set_t = undefined;
        linux.CPU_ZERO(&cpu_set);
        linux.CPU_SET(cpu_id, &cpu_set);
        
        // Set the CPU affinity for the current thread
        const result = linux.sched_setaffinity(0, @sizeOf(linux.cpu_set_t), &cpu_set);
        if (result != 0) {
            return error.SetAffinityFailed;
        }
    }

    fn allocOnNodeLinux(node: usize, size: usize) ![]u8 {
        if (comptime std.Target.current.os.tag != .linux) {
            @compileError("Linux-specific function called on non-Linux platform");
        }

        // Use mmap with MPOL_PREFERRED policy
        const linux = std.os.linux;
        const ptr = linux.mmap(
            null,
            size,
            linux.PROT.READ | linux.PROT.WRITE,
            linux.MAP.PRIVATE | linux.MAP.ANONYMOUS,
            -1,
            0
        );
        
        if (ptr == linux.MAP.FAILED) {
            return error.MmapFailed;
        }
        
        // Set NUMA policy for the memory
        const result = linux.mbind(
            ptr,
            size,
            linux.MPOL.PREFERRED,
            &[_]usize{@as(usize, 1) << @intCast(node)},
            1,
            linux.MPOL.MF_MOVE
        );
        
        if (result != 0) {
            // If mbind fails, we still have the memory, just not on the preferred node
            std.log.warn("Failed to bind memory to NUMA node {d}", .{node});
        }
        
        return @as([*]u8, @ptrCast(ptr))[0..size];
    }

    fn freeOnNodeLinux(node: usize, memory: []u8) void {
        _ = node;
        if (comptime std.Target.current.os.tag != .linux) {
            @compileError("Linux-specific function called on non-Linux platform");
        }

        const linux = std.os.linux;
        _ = linux.munmap(memory.ptr, memory.len);
    }
};

/// NUMA-aware allocator that allocates memory on a specific NUMA node
pub const NumaAllocator = struct {
    parent_allocator: std.mem.Allocator,
    node: usize,

    /// Initialize a new NUMA allocator
    pub fn init(parent_allocator: std.mem.Allocator, node: usize) NumaAllocator {
        return NumaAllocator{
            .parent_allocator = parent_allocator,
            .node = node,
        };
    }

    /// Get an allocator interface
    pub fn allocator(self: *NumaAllocator) std.mem.Allocator {
        return std.mem.Allocator.init(self, alloc, resize, free);
    }

    /// Allocate memory on the NUMA node
    fn alloc(
        ctx: *anyopaque,
        len: usize,
        log2_ptr_align: u8,
        ret_addr: usize,
    ) ?[*]u8 {
        const self = @as(*NumaAllocator, @ptrCast(@alignCast(ctx)));
        
        // For small allocations, use the parent allocator
        if (len < 4096) {
            return self.parent_allocator.rawAlloc(len, log2_ptr_align, ret_addr);
        }
        
        // For large allocations, try to use NUMA-specific allocation
        const memory = Numa.allocOnNode(self.node, len) catch |err| {
            std.log.warn("NUMA allocation failed: {}, falling back to parent allocator", .{err});
            return self.parent_allocator.rawAlloc(len, log2_ptr_align, ret_addr);
        };
        
        return memory.ptr;
    }

    /// Resize memory
    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self = @as(*NumaAllocator, @ptrCast(@alignCast(ctx)));
        
        // For small allocations, use the parent allocator
        if (buf.len < 4096 and new_len < 4096) {
            return self.parent_allocator.rawResize(buf, log2_buf_align, new_len, ret_addr);
        }
        
        // We can't resize NUMA allocations, so always return false
        return false;
    }

    /// Free memory
    fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        ret_addr: usize,
    ) void {
        const self = @as(*NumaAllocator, @ptrCast(@alignCast(ctx)));
        
        // For small allocations, use the parent allocator
        if (buf.len < 4096) {
            return self.parent_allocator.rawFree(buf, log2_buf_align, ret_addr);
        }
        
        // For large allocations, use NUMA-specific free
        Numa.freeOnNode(self.node, buf);
    }
};
