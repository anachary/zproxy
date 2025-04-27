const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Create a module for the gateway library
    const gateway_module = b.addModule("gateway", .{
        .source_file = .{ .path = "src/gateway.zig" },
    });

    // Build the gateway library
    const lib = b.addStaticLibrary(.{
        .name = "gateway",
        .root_source_file = .{ .path = "src/gateway.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Build the gateway executable
    const exe = b.addExecutable(.{
        .name = "gateway",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Create a step for running the gateway
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the gateway");
    run_step.dependOn(&run_cmd.step);

    // Create examples
    const basic_example = b.addExecutable(.{
        .name = "basic_example",
        .root_source_file = .{ .path = "examples/basic.zig" },
        .target = target,
        .optimize = optimize,
    });
    basic_example.addModule("gateway", gateway_module);
    b.installArtifact(basic_example);

    const advanced_example = b.addExecutable(.{
        .name = "advanced_example",
        .root_source_file = .{ .path = "examples/advanced.zig" },
        .target = target,
        .optimize = optimize,
    });
    advanced_example.addModule("gateway", gateway_module);
    b.installArtifact(advanced_example);

    // Static middleware example (using compile-time middleware chain)
    const static_middleware_example = b.addExecutable(.{
        .name = "static_middleware_example",
        .root_source_file = .{ .path = "examples/static_middleware.zig" },
        .target = target,
        .optimize = optimize,
    });
    static_middleware_example.addModule("gateway", gateway_module);
    b.installArtifact(static_middleware_example);

    // Run examples
    const run_basic_example = b.addRunArtifact(basic_example);
    const run_basic_step = b.step("run-basic", "Run the basic example");
    run_basic_step.dependOn(&run_basic_example.step);

    const run_advanced_example = b.addRunArtifact(advanced_example);
    const run_advanced_step = b.step("run-advanced", "Run the advanced example");
    run_advanced_step.dependOn(&run_advanced_example.step);

    // Static middleware example run step
    const run_static_middleware_example = b.addRunArtifact(static_middleware_example);
    const run_static_middleware_step = b.step("run-static-middleware", "Run the static middleware example");
    run_static_middleware_step.dependOn(&run_static_middleware_example.step);

    // Create tests
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/gateway.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
