const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zproxy",
        .root_source_file = .{ .path = "src/main.zig" },
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
    const run_step = b.step("run", "Run the zproxy server");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Benchmark tool
    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_source_file = .{ .path = "benchmarks/benchmark.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(benchmark);
    
    const run_benchmark_cmd = b.addRunArtifact(benchmark);
    run_benchmark_cmd.step.dependOn(b.getInstallStep());
    const run_benchmark_step = b.step("benchmark", "Run benchmarks");
    run_benchmark_step.dependOn(&run_benchmark_cmd.step);
}
