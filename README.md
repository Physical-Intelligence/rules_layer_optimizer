# rules_layer_optimizer

Bazel building blocks for dependency inference, reusable package layers, and
size-aware OCI layer optimization. Use these building blocks to create your own
efficient `py_image` macro.

## Building blocks

| Entrypoint | Symbols | Purpose |
| --- | --- | --- |
| `//layers:defs.bzl` | `layer_group`, `optimized_layers_plan`, `MAX_DOCKER_LAYERS` | Group tar inputs and plan which layers to keep separate or combine |
| `//layers:providers.bzl` | `LayerTarsInfo`, `SizeHintInfo` | Expose ordered layer archives and size estimates to the optimizer |
| `//layers:distroless.bzl` | `optimized_layers` | Create optimized layer archives using rules_distroless |
| `//inference:defs.bzl` | `layer_inference`, `layer_inference_bundle`, `inferred_layers`, `env_inference`, `env_inference_bundle`, `env_file` | Select layers and environment variables from dependency labels |
| `//inference:extensions.bzl` | `oci_image_inference` | Configure dependency traversal and package-size estimates |
| `//apt:defs.bzl` | `apt_inference`, `inferred_apt_deps` | Select APT package layers from application dependencies |
| `//python:aspect_rules_py.bzl` | `py_image_layer`, `pip_layer_reducer` | Split aspect_rules_py binaries into reusable package and source layers |
| `//python:rules_python.bzl` | `py_image_layer`, `pip_layer_reducer` | Split rules_python binaries into interpreter, package, and source layers |
| `//python:inference.bzl` | `layer_inference`, `inferred_layers`, `apt_inference`, `inferred_apt_deps`, `env_inference`, `env_file` | Select layers, APT packages, and environment variables from Python dependencies |

## Get started

Add the dependency to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_layer_optimizer", version = "0.1.0")
```

Given tar-producing targets, group and optimize them in `BUILD.bazel`:

```starlark
load("@rules_layer_optimizer//layers:defs.bzl", "layer_group")
load("@rules_layer_optimizer//layers:distroless.bzl", "optimized_layers")

optimized_layers(
    name = "layers",
    groups = [layer_group(
        name = "packages",
        targets = [":package_a", ":package_b"],
        overflow = "flatten",
    )],
    layer_budget = 10,
    size_bytes_threshold = 1024 * 1024,
    visibility = ["//visibility:public"],
)
```

Inputs with size hints compete for individual layers; unsized inputs are combined
into the group's overflow layer. Only group archives that are safe to reorder.
Pass `:layers` to `oci_image(tars = [...])` or `image_manifest(layers = [...])`.
The [basic example](examples/basic_layers/BUILD.bazel) includes actual tar producers.

See [layers](layers/README.md) for ordering and the API reference,
[Python](python/README.md) for binary layer producers, and
[configuration](docs/configuration.md) for optional inference and size metadata.
For installation from an archive, see [release preparation](.bcr/README.md).

## Try it locally

The [examples module](examples/README.md) demonstrates tar optimization, Python OCI images, and
package-sharing checks. Both Python adapters are tested with rules_oci and
rules_img.

```sh
bazel test //...
(cd examples && bazel test //...)
(cd e2e/minimum && bazel test //...)
(cd e2e/smoke && bazel test //...)
(cd e2e/inference && bazel test //...)
(cd e2e/rules_python && bazel test //...)
```

Start with [configuration](docs/configuration.md) and the capability docs:
[layers](layers/README.md), [inference](inference/README.md),
[Python](python/README.md), and [APT](apt/README.md).
See [compatibility](docs/compatibility.md) for supported dependency minimums and
[CONTRIBUTING.md](CONTRIBUTING.md) for development checks.
