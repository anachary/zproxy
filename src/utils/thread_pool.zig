const std = @import("std");
const numa = @import("numa.zig");

/// A lock-free queue for jobs
pub const LockFreeQueue = struct {
    const Node = struct {
        next: ?*Node,
        data: Job,
    };

    head: std.atomic.Value(*Node),
    tail: std.atomic.Value(*Node),
    allocator: std.mem.Allocator,
    
    /// A job to be executed by the thread pool
    pub const Job = struct {
        function: *const fn (context: *anyopaque) void,
        context: *anyopaque,
    };

    /// Initialize a new lock-free queue
    pub fn init(allocator: std.mem.Allocator) !LockFreeQueue {
        // Create a dummy node
        var dummy = try allocator.create(Node);
        dummy.* = .{
            .next = null,
            .data = undefined,
        };

        return LockFreeQueue{
            .head = std.atomic.Value(*Node).init(dummy),
            .tail = std.atomic.Value(*Node).init(dummy),
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *LockFreeQueue) void {
        // Free all nodes
        var current = self.head.load(.Acquire);
        while (current) |node| {
            const next = node.next;
            self.allocator.destroy(node);
            current = next;
        }
    }

    /// Enqueue a job
    pub fn enqueue(self: *LockFreeQueue, job: Job) !void {
        // Create a new node
        var node = try self.allocator.create(Node);
        node.* = .{
            .next = null,
            .data = job,
        };

        // Add the node to the queue
        while (true) {
            const tail = self.tail.load(.Acquire);
            const next = tail.next;

            // Check if tail is still the last node
            if (tail == self.tail.load(.Acquire)) {
                if (next == null) {
                    // Try to link the new node
                    if (tail.next == null and 
                        @cmpxchgStrong(?*Node, &tail.next, null, node, .Release, .Monotonic) == null) {
                        // Update the tail pointer
                        _ = self.tail.compareAndSwap(tail, node, .Release, .Monotonic);
                        return;
                    }
                } else {
                    // Tail is falling behind, help advance it
                    _ = self.tail.compareAndSwap(tail, next.?, .Release, .Monotonic);
                }
            }
        }
    }

    /// Dequeue a job
    pub fn dequeue(self: *LockFreeQueue) ?Job {
        while (true) {
            const head = self.head.load(.Acquire);
            const tail = self.tail.load(.Acquire);
            const next = head.next;

            // Check if head is still valid
            if (head == self.head.load(.Acquire)) {
                // Check if queue is empty
                if (head == tail) {
                    if (next == null) {
                        // Queue is empty
                        return null;
                    }
                    // Tail is falling behind, help advance it
                    _ = self.tail.compareAndSwap(tail, next.?, .Release, .Monotonic);
                } else {
                    // Get the job from the next node
                    if (next) |node| {
                        const job = node.data;
                        // Try to advance head
                        if (self.head.compareAndSwap(head, node, .Release, .Monotonic) == head) {
                            // Successfully dequeued
                            self.allocator.destroy(head);
                            return job;
                        }
                    } else {
                        // Queue is empty
                        return null;
                    }
                }
            }
        }
    }
};

/// A NUMA-aware thread pool
pub const NumaThreadPool = struct {
    allocator: std.mem.Allocator,
    node_pools: []NodePool,
    shutdown_requested: std.atomic.Atomic(bool),
    
    /// A pool of threads for a specific NUMA node
    const NodePool = struct {
        allocator: std.mem.Allocator,
        node: usize,
        threads: []std.Thread,
        job_queue: LockFreeQueue,
        numa_allocator: numa.NumaAllocator,
        shutdown_requested: *std.atomic.Atomic(bool),
        semaphore: std.Thread.Semaphore,
        
        /// Initialize a new node pool
        pub fn init(
            allocator: std.mem.Allocator,
            node: usize,
            thread_count: usize,
            shutdown_requested: *std.atomic.Atomic(bool),
        ) !NodePool {
            var numa_allocator = numa.NumaAllocator.init(allocator, node);
            const node_allocator = numa_allocator.allocator();
            
            var job_queue = try LockFreeQueue.init(node_allocator);
            errdefer job_queue.deinit();
            
            var threads = try allocator.alloc(std.Thread, thread_count);
            errdefer allocator.free(threads);
            
            var pool = NodePool{
                .allocator = allocator,
                .node = node,
                .threads = threads,
                .job_queue = job_queue,
                .numa_allocator = numa_allocator,
                .shutdown_requested = shutdown_requested,
                .semaphore = std.Thread.Semaphore{},
            };
            
            // Get CPUs for this NUMA node
            var node_cpus = try numa.Numa.getCpusForNumaNode(node, allocator);
            defer allocator.free(node_cpus);
            
            // Create worker threads
            for (threads, 0..) |*thread, i| {
                const cpu_id = node_cpus[i % node_cpus.len];
                thread.* = try std.Thread.spawn(.{}, workerThread, .{ 
                    &pool, 
                    i, 
                    cpu_id,
                });
            }
            
            return pool;
        }
        
        /// Clean up resources
        pub fn deinit(self: *NodePool) void {
            // Wait for all threads to finish
            for (self.threads) |thread| {
                thread.join();
            }
            
            // Clean up resources
            self.allocator.free(self.threads);
            self.job_queue.deinit();
        }
        
        /// Add a job to the queue
        pub fn addJob(self: *NodePool, job: LockFreeQueue.Job) !void {
            try self.job_queue.enqueue(job);
            self.semaphore.post();
        }
        
        /// Worker thread function
        fn workerThread(pool: *NodePool, thread_id: usize, cpu_id: usize) !void {
            const logger = std.log.scoped(.thread_pool);
            logger.debug("Worker thread {d} started on NUMA node {d}, CPU {d}", .{
                thread_id, 
                pool.node, 
                cpu_id,
            });
            
            // Set CPU affinity
            try numa.Numa.setThreadAffinity(cpu_id);
            
            while (!pool.shutdown_requested.load(.Acquire)) {
                // Try to get a job
                if (pool.job_queue.dequeue()) |job| {
                    // Execute the job
                    job.function(job.context);
                    continue;
                }
                
                // No job available, wait for one
                pool.semaphore.wait();
                
                // Check if shutdown was requested while waiting
                if (pool.shutdown_requested.load(.Acquire)) {
                    break;
                }
            }
            
            logger.debug("Worker thread {d} on NUMA node {d} shutting down", .{
                thread_id, 
                pool.node,
            });
        }
    };
    
    /// Initialize a new NUMA-aware thread pool
    pub fn init(allocator: std.mem.Allocator) !NumaThreadPool {
        // Get the number of NUMA nodes
        const node_count = try numa.Numa.getNumaNodeCount();
        
        // Create a pool for each NUMA node
        var node_pools = try allocator.alloc(NodePool, node_count);
        errdefer allocator.free(node_pools);
        
        var shutdown_requested = std.atomic.Atomic(bool).init(false);
        
        // Initialize each node pool
        var i: usize = 0;
        errdefer {
            // Clean up initialized pools
            while (i > 0) {
                i -= 1;
                node_pools[i].deinit();
            }
        }
        
        while (i < node_count) : (i += 1) {
            // Get the number of CPUs for this node
            var node_cpus = try numa.Numa.getCpusForNumaNode(i, allocator);
            const thread_count = node_cpus.len;
            allocator.free(node_cpus);
            
            // Initialize the node pool
            node_pools[i] = try NodePool.init(
                allocator,
                i,
                thread_count,
                &shutdown_requested,
            );
        }
        
        return NumaThreadPool{
            .allocator = allocator,
            .node_pools = node_pools,
            .shutdown_requested = shutdown_requested,
        };
    }
    
    /// Clean up resources
    pub fn deinit(self: *NumaThreadPool) void {
        // Signal shutdown
        self.shutdown_requested.store(true, .Release);
        
        // Wake up all threads
        for (self.node_pools) |*pool| {
            for (pool.threads) |_| {
                pool.semaphore.post();
            }
        }
        
        // Clean up each node pool
        for (self.node_pools) |*pool| {
            pool.deinit();
        }
        
        // Free the node pools array
        self.allocator.free(self.node_pools);
    }
    
    /// Add a job to the thread pool
    pub fn addJob(
        self: *NumaThreadPool, 
        function: *const fn (context: *anyopaque) void, 
        context: *anyopaque,
        preferred_node: ?usize,
    ) !void {
        const job = LockFreeQueue.Job{
            .function = function,
            .context = context,
        };
        
        if (preferred_node) |node| {
            // Try to add the job to the preferred node
            if (node < self.node_pools.len) {
                try self.node_pools[node].addJob(job);
                return;
            }
        }
        
        // No preferred node or invalid node, use round-robin
        const node = @mod(@as(usize, @intFromPtr(context)), self.node_pools.len);
        try self.node_pools[node].addJob(job);
    }
    
    /// Get the number of NUMA nodes
    pub fn getNodeCount(self: *NumaThreadPool) usize {
        return self.node_pools.len;
    }
    
    /// Get the total number of threads
    pub fn getThreadCount(self: *NumaThreadPool) usize {
        var count: usize = 0;
        for (self.node_pools) |pool| {
            count += pool.threads.len;
        }
        return count;
    }
};
