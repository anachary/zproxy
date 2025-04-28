# build.zig Documentation

## Overview

The `build.zig` file defines the build configuration for the ZProxy project using Zig's build system. It sets up the main executable, tests, and benchmarking tools.

## Key Components

### Target and Optimization

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});
```

These lines allow the user to specify the target platform and optimization level when running the build command. For example:

- `zig build -Dtarget=x86_64-windows` to target Windows
- `zig build -Doptimize=ReleaseFast` for maximum performance

### Main Executable

```zig
const exe = b.addExecutable(.{
    .name = "zproxy",
    .root_source_file = .{ .path = "src/main.zig" },
    .target = target,
    .optimize = optimize,
});
b.installArtifact(exe);
```

This creates the main ZProxy executable with the entry point at `src/main.zig`.

### Run Command

```zig
const run_cmd = b.addRunArtifact(exe);
run_cmd.step.dependOn(b.getInstallStep());
if (b.args) |args| {
    run_cmd.addArgs(args);
}
const run_step = b.step("run", "Run the zproxy server");
run_step.dependOn(&run_cmd.step);
```

This creates a `run` step that allows running the ZProxy server with `zig build run`. It also forwards any command-line arguments to the executable.

### Tests

```zig
const unit_tests = b.addTest(.{
    .root_source_file = .{ .path = "src/main.zig" },
    .target = target,
    .optimize = optimize,
});
const run_unit_tests = b.addRunArtifact(unit_tests);
const test_step = b.step("test", "Run unit tests");
test_step.dependOn(&run_unit_tests.step);
```

This creates a `test` step that runs all tests in the project with `zig build test`.

### Benchmark Tool

```zig
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
```

This creates a benchmark tool and a `benchmark` step that can be run with `zig build benchmark`.

## Zig Build System Principles

1. **Declarative**: The build file describes what to build, not how to build it.
2. **Dependency-based**: Steps depend on other steps, forming a directed acyclic graph.
3. **Cross-compilation**: The build system supports building for different targets.
4. **Optimization levels**: Different optimization levels can be specified for different builds.

## Usage

- `zig build` - Build the project
- `zig build run` - Build and run the ZProxy server
- `zig build test` - Run all tests
- `zig build benchmark` - Run benchmarks
- `zig build -Doptimize=ReleaseFast` - Build with maximum optimization
- `zig build -Dtarget=x86_64-linux-gnu` - Build for a specific target
