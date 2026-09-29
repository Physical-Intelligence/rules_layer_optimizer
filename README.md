# rules_layer_optimizer

Bazel building blocks for dependency inference, reusable package layers, and
size-aware OCI layer optimization. Consumers own their image assembly macros,
base packages, inference mappings, and image backend. There is no supported
`py_image` macro.

This repository is private and under development. Version `0.0.0` is not a
published release. No releases or registry publication are enabled.

## Building blocks

| Public entrypoint | Purpose |
| --- | --- |
| `//layers:defs.bzl` | `layer_group`, `optimized_layers_plan`, `MAX_DOCKER_LAYERS` |
| `//layers:providers.bzl` | `LayerTarsInfo`, `SizeHintInfo` |
| `//layers:distroless.bzl` | `optimized_layers` materialization with rules_distroless |
| `//inference:defs.bzl` | Exact-label layer and environment inference |
| `//inference:extensions.bzl` | Root-module graph and package-size configuration |
| `//apt:defs.bzl` | `apt_inference`, `inferred_apt_deps` |
| `//python:aspect_rules_py.bzl` | aspect_rules_py layers and source bucket helpers (`defs.bzl` alias) |
| `//python:rules_python.bzl` | rules_python interpreter, package, and source layers |
| `//python:inference.bzl` | Pip-aware layer, APT, and environment inference |

## Try it locally

The [examples module](examples/README.md) is a standalone consumer using
`local_path_override`. It includes tar optimization, a Python OCI image, and
package-sharing checks. Both Python adapters are tested with rules_oci and
rules_img.

```sh
bazel test //...
(cd examples && bazel test //...)
(cd e2e/smoke && bazel test //...)
(cd e2e/rules_python && bazel test //...)
```

Start with [configuration](docs/configuration.md) and the capability docs:
[layers](layers/README.md), [inference](inference/README.md),
[Python](python/README.md), and [APT](apt/README.md).
See [CONTRIBUTING.md](CONTRIBUTING.md) for development checks.
