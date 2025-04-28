# Contributing to ZProxy

Thank you for your interest in contributing to ZProxy! This document provides guidelines and instructions for contributing to the project.

## Code of Conduct

Please be respectful and considerate of others when contributing to ZProxy. We strive to maintain a welcoming and inclusive community.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/yourusername/zproxy.git`
3. Create a feature branch: `git checkout -b feature/amazing-feature`
4. Make your changes
5. Run tests: `zig build test`
6. Commit your changes: `git commit -m 'Add some amazing feature'`
7. Push to the branch: `git push origin feature/amazing-feature`
8. Open a Pull Request

## Development Environment

To set up your development environment:

1. Install [Zig](https://ziglang.org/download/) 0.11.0 or later
2. Install [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell) 5.0 or later (for running scripts on Windows)
3. Clone the repository: `git clone https://github.com/yourusername/zproxy.git`
4. Build the project: `zig build`
5. Run tests: `zig build test`

## Project Structure

```
zproxy/
├── src/                  # Source code
│   ├── main.zig          # Entry point
│   ├── config/           # Configuration
│   ├── server/           # Server implementation
│   ├── protocol/         # Protocol handlers
│   ├── router/           # Routing
│   ├── proxy/            # Proxying
│   ├── middleware/       # Middleware
│   ├── tls/              # TLS support
│   └── utils/            # Utilities
├── tests/                # Tests
├── benchmarks/           # Benchmarks
├── examples/             # Example configurations
└── docs/                 # Documentation
```

## Coding Standards

### General Guidelines

- Follow the [Zig Style Guide](https://ziglang.org/documentation/master/#Style-Guide)
- Write clear, concise, and descriptive code
- Use meaningful variable and function names
- Keep functions small and focused
- Add comments for complex logic
- Write tests for new features

### Naming Conventions

- Use `camelCase` for variables and functions
- Use `PascalCase` for types and structs
- Use `snake_case` for file names
- Use `SCREAMING_SNAKE_CASE` for constants

### Error Handling

- Use Zig's error handling features
- Propagate errors up the call stack
- Provide descriptive error messages
- Handle all possible error cases

### Memory Management

- Use Zig's memory safety features
- Avoid memory leaks
- Free allocated memory
- Use custom allocators for performance-critical paths

## Testing

- Write tests for new features
- Run tests before submitting a pull request
- Add benchmarks for performance-critical code
- Test edge cases and error conditions

To run tests:

```bash
zig build test
```

## Documentation

- Update documentation for new features
- Write clear and concise documentation
- Include examples where appropriate
- Keep the documentation up to date

## Pull Request Process

1. Ensure your code follows the coding standards
2. Update the documentation
3. Add tests for new features
4. Run tests to ensure they pass
5. Submit a pull request
6. Address review comments
7. Once approved, your pull request will be merged

## Reporting Bugs

If you find a bug, please report it by creating an issue on GitHub. Include:

- A clear and descriptive title
- Steps to reproduce the bug
- Expected behavior
- Actual behavior
- Screenshots or logs if applicable
- Environment information (OS, Zig version, etc.)

## Feature Requests

If you have a feature request, please create an issue on GitHub. Include:

- A clear and descriptive title
- A detailed description of the feature
- Why the feature would be useful
- Any relevant examples or use cases

## License

By contributing to ZProxy, you agree that your contributions will be licensed under the project's license.
