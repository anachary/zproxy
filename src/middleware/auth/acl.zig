const std = @import("std");
const types = @import("../types.zig");

/// Access Control List middleware
pub const AclMiddleware = struct {
    allocator: std.mem.Allocator,
    rules: std.ArrayList(AclRule),

    /// ACL rule
    const AclRule = struct {
        path: []const u8,
        methods: []const []const u8,
        roles: []const []const u8,
    };

    /// Create a new ACL middleware
    pub fn create(allocator: std.mem.Allocator, config: anytype) !*types.Middleware {
        var middleware = try allocator.create(AclMiddleware);

        var rules = std.ArrayList(AclRule).init(allocator);

        // Parse ACL rules from config
        if (@hasField(@TypeOf(config), "acl_rules")) {
            for (config.acl_rules) |rule_config| {
                // Copy methods
                var methods = try allocator.alloc([]const u8, rule_config.methods.len);
                for (rule_config.methods, 0..) |method, i| {
                    methods[i] = try allocator.dupe(u8, method);
                }

                // Copy roles
                var roles = try allocator.alloc([]const u8, rule_config.roles.len);
                for (rule_config.roles, 0..) |role, i| {
                    roles[i] = try allocator.dupe(u8, role);
                }

                // Create rule
                try rules.append(AclRule{
                    .path = try allocator.dupe(u8, rule_config.path),
                    .methods = methods,
                    .roles = roles,
                });
            }
        }

        middleware.* = AclMiddleware{
            .allocator = allocator,
            .rules = rules,
        };

        return @ptrCast(middleware);
    }

    /// Clean up resources
    pub fn deinit(self: *AclMiddleware) void {
        for (self.rules.items) |*rule| {
            self.allocator.free(rule.path);

            for (rule.methods) |method| {
                self.allocator.free(method);
            }
            self.allocator.free(rule.methods);

            for (rule.roles) |role| {
                self.allocator.free(role);
            }
            self.allocator.free(rule.roles);
        }

        self.rules.deinit();
    }

    /// Process a request
    pub fn process(self: *const AclMiddleware, context: *types.Context) !types.Result {
        // Get user roles from context
        const user_roles = try self.getUserRoles(context);
        defer self.allocator.free(user_roles);

        // Find matching rule
        const rule = try self.findMatchingRule(context.request.path, context.request.method);
        if (rule == null) {
            // No rule found, allow access
            return types.Result{ .success = true };
        }

        // Check if user has required role
        for (rule.?.roles) |required_role| {
            for (user_roles) |user_role| {
                if (std.mem.eql(u8, required_role, user_role)) {
                    // User has required role, allow access
                    return types.Result{ .success = true };
                }
            }
        }

        // User doesn't have required role, deny access
        return types.Result{
            .success = false,
            .status_code = 403,
            .error_message = "Access denied",
        };
    }

    /// Get user roles from context
    fn getUserRoles(self: *const AclMiddleware, context: *types.Context) ![]const []const u8 {
        // In a real implementation, this would extract roles from JWT claims
        // or other authentication information in the context
        _ = context;

        // For simplicity, we'll just return a placeholder role
        var roles = try self.allocator.alloc([]const u8, 1);
        roles[0] = try self.allocator.dupe(u8, "user");

        return roles;
    }

    /// Find a rule matching the given path and method
    fn findMatchingRule(self: *const AclMiddleware, path: []const u8, method: []const u8) !?*const AclRule {
        for (self.rules.items) |*rule| {
            // Check if path matches
            if (!std.mem.startsWith(u8, path, rule.path)) {
                continue;
            }

            // Check if method matches
            var method_matches = false;
            for (rule.methods) |allowed_method| {
                if (std.mem.eql(u8, method, allowed_method)) {
                    method_matches = true;
                    break;
                }
            }

            if (!method_matches) {
                continue;
            }

            return rule;
        }

        return null;
    }
};
