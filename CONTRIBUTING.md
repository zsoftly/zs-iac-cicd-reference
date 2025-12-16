# Contributing to IaC CI/CD Reference

Thank you for your interest in contributing! This document provides guidelines for contributing to
this repository.

## How to Contribute

### Reporting Issues

- Use GitHub Issues to report bugs or suggest features
- Include CI/CD platform, cloud provider, and tool versions
- Provide minimal reproduction steps

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test your changes
5. Commit with clear messages
6. Push and create a Pull Request

## Code Standards

### Terraform

- Use `terraform fmt` before committing
- Include variable descriptions and types
- Add README for each module
- Use meaningful resource names

### Ansible

- Follow ansible-lint rules
- Use FQCN for modules (e.g., `ansible.builtin.copy`)
- Include role defaults and documentation
- Test with `--check` mode

### Shell Scripts

- Use `set -euo pipefail`
- Include usage documentation
- Handle errors gracefully
- Clean up temporary files

### YAML (Pipelines)

- Use consistent indentation (2 spaces)
- Include comments for complex logic
- Use descriptive job/stage names

## Testing

Before submitting:

1. **Terraform**: `terraform fmt -check && terraform validate`
2. **Ansible**: `ansible-lint && ansible-playbook --syntax-check`
3. **Shell**: `shellcheck scripts/*.sh`

## Documentation

- Update README if adding new features
- Include examples in docs/
- Keep comments concise and helpful

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
