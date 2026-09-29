# rules_layer_optimizer

Bazel building blocks for dependency inference, reusable package layers, and
size-aware OCI layer optimization.

This repository is under construction. It currently contains the repository
scaffold; the rules and examples have not been extracted yet. There is no
released API or Bazel Central Registry module.

## Scope

The library will provide ordered layer planning, shared size budgets, package
size metadata, dependency-triggered layers and environment variables, and Python
layer production. Consumers own their image assembly macros, base packages,
inference mappings, and choice of image backend. A `py_image` macro is explicitly
outside the supported API.

## Layout

| Directory | Responsibility |
| --- | --- |
| [layers](layers/README.md) | Generic planning, public providers, and materialization adapters |
| [inference](inference/README.md) | Dependency graph matching and module configuration |
| [python](python/README.md) | Python package and runfiles layers |
| [apt](apt/README.md) | APT inference and package size hints |
| [examples](examples/README.md) | Consumer-owned assembly using the public API |
| [e2e/smoke](e2e/smoke/README.md) | Minimal external-consumer validation |
| [docs](docs/README.md) | Architecture and API documentation |

See [CONTRIBUTING.md](CONTRIBUTING.md) for local checks.
