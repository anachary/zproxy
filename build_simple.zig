const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Simple executable
    const exe = b.addExecutable(.{
        .name = "zproxy_simple",
        .root_source_file = .{ .path = "src/main_simple.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the simple app");
    run_step.dependOn(&run_cmd.step);
}
