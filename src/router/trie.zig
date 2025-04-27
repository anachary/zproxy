const std = @import("std");

/// A node in the trie
pub const TrieNode = struct {
    allocator: std.mem.Allocator,
    children: std.StringHashMap(*TrieNode),
    is_terminal: bool,
    route_index: ?usize,
    param_name: ?[]const u8,
    wildcard: bool,

    /// Initialize a new trie node
    pub fn init(allocator: std.mem.Allocator) !*TrieNode {
        var node = try allocator.create(TrieNode);
        node.* = TrieNode{
            .allocator = allocator,
            .children = std.StringHashMap(*TrieNode).init(allocator),
            .is_terminal = false,
            .route_index = null,
            .param_name = null,
            .wildcard = false,
        };
        return node;
    }

    /// Clean up resources
    pub fn deinit(self: *TrieNode) void {
        var it = self.children.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.children.deinit();
        if (self.param_name) |name| {
            self.allocator.free(name);
        }
    }

    /// Insert a path into the trie
    pub fn insert(self: *TrieNode, path: []const u8, route_index: usize) !void {
        var current = self;
        var i: usize = 0;

        while (i < path.len) {
            // Skip multiple slashes
            if (path[i] == '/' and (i == 0 or path[i - 1] == '/')) {
                i += 1;
                continue;
            }

            // Find the end of the current segment
            var segment_start = i;
            while (i < path.len and path[i] != '/') {
                i += 1;
            }
            var segment = path[segment_start..i];

            // Handle parameter segments (:param)
            if (segment.len > 0 and segment[0] == ':') {
                const param_name = segment[1..];
                var param_node: *TrieNode = undefined;

                // Check if we already have a parameter child
                var param_found = false;
                var it = current.children.iterator();
                while (it.next()) |entry| {
                    if (entry.value_ptr.*.param_name != null) {
                        param_node = entry.value_ptr.*;
                        param_found = true;
                        break;
                    }
                }

                if (!param_found) {
                    // Create a new parameter node
                    param_node = try TrieNode.init(self.allocator);
                    param_node.param_name = try self.allocator.dupe(u8, param_name);
                    try current.children.put(":", param_node);
                }

                current = param_node;
            }
            // Handle wildcard segments (*)
            else if (std.mem.eql(u8, segment, "*")) {
                var wildcard_node: *TrieNode = undefined;

                // Check if we already have a wildcard child
                if (current.children.get("*")) |node| {
                    wildcard_node = node;
                } else {
                    // Create a new wildcard node
                    wildcard_node = try TrieNode.init(self.allocator);
                    wildcard_node.wildcard = true;
                    try current.children.put("*", wildcard_node);
                }

                current = wildcard_node;
                // Wildcard must be the last segment
                i = path.len;
            }
            // Regular segment
            else {
                var next: *TrieNode = undefined;

                if (current.children.get(segment)) |node| {
                    next = node;
                } else {
                    next = try TrieNode.init(self.allocator);
                    try current.children.put(try self.allocator.dupe(u8, segment), next);
                }

                current = next;
            }

            // Skip the slash
            if (i < path.len and path[i] == '/') {
                i += 1;
            }
        }

        // Mark the last node as terminal
        current.is_terminal = true;
        current.route_index = route_index;
    }

    /// Find a route matching the given path
    pub fn find(self: *TrieNode, path: []const u8, params: *std.StringHashMap([]const u8)) !?usize {
        var current = self;
        var i: usize = 0;

        while (i < path.len) {
            // Skip multiple slashes
            if (path[i] == '/' and (i == 0 or path[i - 1] == '/')) {
                i += 1;
                continue;
            }

            // Find the end of the current segment
            var segment_start = i;
            while (i < path.len and path[i] != '/') {
                i += 1;
            }
            var segment = path[segment_start..i];

            // Try to match a static segment first
            if (current.children.get(segment)) |node| {
                current = node;
            }
            // Try to match a parameter segment
            else if (current.children.get(":")) |param_node| {
                current = param_node;
                if (param_node.param_name) |name| {
                    try params.put(name, segment);
                }
            }
            // Try to match a wildcard
            else if (current.children.get("*")) |wildcard_node| {
                return wildcard_node.route_index;
            }
            // No match found
            else {
                return null;
            }

            // Skip the slash
            if (i < path.len and path[i] == '/') {
                i += 1;
            }
        }

        // Check if we reached a terminal node
        if (current.is_terminal) {
            return current.route_index;
        }

        // Check for a wildcard child at the end
        if (current.children.get("*")) |wildcard_node| {
            return wildcard_node.route_index;
        }

        return null;
    }
};

/// A trie-based router for fast path matching
pub const TrieRouter = struct {
    allocator: std.mem.Allocator,
    root: *TrieNode,
    method_tries: std.StringHashMap(*TrieNode),

    /// Initialize a new trie router
    pub fn init(allocator: std.mem.Allocator) !TrieRouter {
        var root = try TrieNode.init(allocator);
        errdefer {
            root.deinit();
            allocator.destroy(root);
        }

        return TrieRouter{
            .allocator = allocator,
            .root = root,
            .method_tries = std.StringHashMap(*TrieNode).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *TrieRouter) void {
        self.root.deinit();
        self.allocator.destroy(self.root);

        var it = self.method_tries.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.method_tries.deinit();
    }

    /// Add a route to the router
    pub fn addRoute(self: *TrieRouter, method: []const u8, path: []const u8, route_index: usize) !void {
        // Get or create the trie for this method
        var method_trie: *TrieNode = undefined;
        if (self.method_tries.get(method)) |trie| {
            method_trie = trie;
        } else {
            method_trie = try TrieNode.init(self.allocator);
            try self.method_tries.put(try self.allocator.dupe(u8, method), method_trie);
        }

        // Insert the route into the method trie
        try method_trie.insert(path, route_index);

        // Also insert into the root trie (for method-agnostic lookups)
        try self.root.insert(path, route_index);
    }

    /// Find a route matching the given path and method
    pub fn findRoute(self: *TrieRouter, method: []const u8, path: []const u8) !?usize {
        var params = std.StringHashMap([]const u8).init(self.allocator);
        defer params.deinit();

        // Try to find a route for this method
        if (self.method_tries.get(method)) |method_trie| {
            if (try method_trie.find(path, &params)) |route_index| {
                return route_index;
            }
        }

        // If no method-specific route was found, try the ANY method
        if (self.method_tries.get("ANY")) |any_trie| {
            if (try any_trie.find(path, &params)) |route_index| {
                return route_index;
            }
        }

        return null;
    }
};

// Tests
test "TrieRouter basic functionality" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var router = try TrieRouter.init(allocator);
    defer router.deinit();

    // Add some routes
    try router.addRoute("GET", "/api/users", 0);
    try router.addRoute("POST", "/api/users", 1);
    try router.addRoute("GET", "/api/users/:id", 2);
    try router.addRoute("GET", "/api/products", 3);
    try router.addRoute("GET", "/api/*", 4);

    // Test route matching
    try testing.expectEqual(@as(?usize, 0), try router.findRoute("GET", "/api/users"));
    try testing.expectEqual(@as(?usize, 1), try router.findRoute("POST", "/api/users"));
    try testing.expectEqual(@as(?usize, 2), try router.findRoute("GET", "/api/users/123"));
    try testing.expectEqual(@as(?usize, 3), try router.findRoute("GET", "/api/products"));
    try testing.expectEqual(@as(?usize, 4), try router.findRoute("GET", "/api/anything"));
    try testing.expectEqual(@as(?usize, null), try router.findRoute("DELETE", "/api/users"));
}
