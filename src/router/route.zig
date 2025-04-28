const std = @import("std");
const config = @import("../config/config.zig");

/// Route parameter
pub const RouteParam = struct {
    name: []const u8,
    value: []const u8,
};

/// Route match result
pub const RouteMatch = struct {
    route: *const config.Route,
    params: []RouteParam,
    
    pub fn deinit(self: *RouteMatch, allocator: std.mem.Allocator) void {
        for (self.params) |param| {
            allocator.free(param.name);
            allocator.free(param.value);
        }
        allocator.free(self.params);
    }
};
