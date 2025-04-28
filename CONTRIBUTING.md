# Contributing to ZProxy

Thank you for your interest in contributing to ZProxy! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

Please be respectful and considerate of others when contributing to ZProxy. We aim to foster an inclusive and welcoming community.

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork to your local machine.
3. Set up the development environment.
4. Make your changes.
5. Test your changes.
6. Submit a pull request.

## Development Environment

ZProxy requires Zig 0.11.0 or later. You can download Zig from [ziglang.org](https://ziglang.org/download/).

To set up the development environment:

```bash
# Clone the repository
git clone https://github.com/yourusername/zproxy.git
cd zproxy

# Build the project
zig build

# Run tests
zig build test

# Run benchmarks
zig build benchmark
```

## Project Structure

```
zproxy/
├── src/                  # Source code
│   ├── config/           # Configuration
│   ├── server/           # Server implementation
│   ├── protocol/         # Protocol handlers
│   ├── router/           # Routing
│   ├── middleware/       # Middleware
│   └── utils/            # Utilities
├── tests/                # Tests
├── benchmarks/           # Benchmarks
├── config/               # Configuration files
├── scripts/              # Scripts
└── docs/                 # Documentation
```

## Coding Standards

- Follow the [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide).
- Write clear, concise, and descriptive code.
- Document your code with comments.
- Write tests for your code.
- Keep performance in mind.

## Pull Request Process

1. Ensure your code follows the coding standards.
2. Update the documentation if necessary.
3. Add tests for your changes.
4. Make sure all tests pass.
5. Submit a pull request with a clear description of the changes.

## Reporting Bugs

If you find a bug, please report it by creating an issue on GitHub. Include:

- A clear and descriptive title.
- Steps to reproduce the bug.
- Expected behavior.
- Actual behavior.
- Any relevant logs or screenshots.

## Suggesting Enhancements

If you have an idea for an enhancement, please create an issue on GitHub. Include:

- A clear and descriptive title.
- A detailed description of the enhancement.
- Any relevant examples or mockups.

## Documentation

Documentation is an important part of ZProxy. Please help improve it by:

- Fixing typos or errors.
- Adding examples or tutorials.
- Clarifying confusing sections.
- Adding missing documentation.

## Testing

ZProxy uses Zig's built-in testing framework. To run tests:

```bash
zig build test
```

When adding new features, please add tests to cover your code.

## Benchmarking

ZProxy includes benchmarking tools to measure performance. To run benchmarks:

```bash
zig build benchmark
```

When making performance-related changes, please include benchmark results in your pull request.

## License

By contributing to ZProxy, you agree that your contributions will be licensed under the project's MIT license.
