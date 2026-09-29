# Standalone rules_python consumer

Run `bazel test //...` here to package and execute a rules_python binary from
its extracted layers. This independent module uses rules_python's own Python
3.12 toolchain, pip.parse with a hashed requirements.txt, and explicit size hints
without uv. It registers no aspect_rules_py toolchains.

The runtime test extracts the optimized archive and executes its launcher,
checking package imports, distribution metadata, and inferred environment. It
also checks that the transitive `six` dependency gets its own layer without
duplicating files across package archives.
The [examples matrix](../../examples/README.md) additionally validates both
image backends in Docker.
