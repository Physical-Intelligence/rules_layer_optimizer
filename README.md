# rules_layer_optimizer

This Bazel ruleset provides building blocks for creating optimized application OCI images based on an executable entrypoint, e.g. a `py_binary` target. It provides dependency inference, reusable package layers, and size-aware OCI layer optimization. It provides everything you need to create your own efficient `py_image` macro.

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

## How to use it

Add the dependency to your `MODULE.bazel`:

```starlark
bazel_dep(name = "rules_layer_optimizer", version = "0.1.0")
```

Then, there are 3 basic steps. Each stage is modular, so hand-rolled replacements work fine too.

### 1. Produce layer candidates with size hints

This is the step with the most variability, as it depends on which dependencies your repo uses (`rules_oci` | `rules_img`, and `rules_python` | `aspect_rules_py`). Regardless of your choices, the goal remains the same: produce candidate image layers that are efficient and also accompanied by size hints via the `SizeHintInfo` provider:

```starlark
TODO
```

### 2. Optimize the layers

From the layer candidates, group and optimize them with `optimized_layers`. Note that `SizeHintInfo` is not required on all candidates, the rule will use the hints when available but they only matter for groups where in-group reordering and flattening is desired:

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

### 3. Build the image

The output of `optimized_layers` can be fed directly into `oci_image` or `image_manifest`:

```starlark
TODO
```

## Try it locally

The [examples module](examples/README.md) demonstrates tar optimization, Python OCI images, and
package-sharing checks. Both Python adapters are tested with `rules_oci` and
`rules_img`.

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
