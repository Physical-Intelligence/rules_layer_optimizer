# Agent guidance

Read [README.md](README.md) and [CONTRIBUTING.md](CONTRIBUTING.md) before changes.

- Keep the repository private. Public visibility, releases, and BCR publication
  require Jimmy's explicit approval.
- Provide building blocks; do not add a supported `py_image` macro.
- Use Bazel for builds and tests. Every implementation change needs focused tests.
- Keep public entrypoints separate from `private/` implementations.
- Use Graphite for commits and draft PRs; run pre-commit hooks and follow CI.
- Never clear Bazel caches without explicit permission.
