# Python layers

Choose the entrypoint matching your Python rules:

| Entrypoint | Layer outputs |
| --- | --- |
| `python:aspect_rules_py.bzl` | Pip, source, source buckets, PyO3; caller supplies interpreter |
| `python:rules_python.bzl` | Pip, source, interpreter selected by the binary |

`python:defs.bzl` remains an alias for the aspect_rules_py adapter. Both adapters
export `py_image_layer` and `pip_layer_reducer`; image assembly belongs to callers.

`pip_layer_reducer(deps = [...])` collects one tar per distribution and exposes
LayerTarsInfo and SizeHintInfo. Actions belong to the wheel target, so binaries
selecting the same wheel reuse the same artifact. Reaching distinct wheels for
one normalized distribution is rejected. Both adapters share collection,
ordering, conflict checks, inference, and virtualenv symlink preservation.

## aspect_rules_py

`py_image_layer` splits binary runfiles into source, source buckets, and PyO3
artifacts. Supply `binary`, `interpreter_tar`, `python_toolchain`, and
`source_dep_buckets` (an empty list is valid). Use `root = "/app"` and a
`strip_prefix` corresponding to the binary label's `package/name`. The
interpreter tar must install under the binary's runfiles repository path.

Outputs are `<name>_pip`, `<name>_source`, `<name>_source_deps`, `<name>_pyo3`,
and composite `<name>`, `<name>_no_src`, and `<name>_only_src` targets. The adapter
preserves the installed wheel tree, including distribution metadata, and uses
the selected wheel filename for exact compressed-size hints.

## rules_python

```starlark
load("@rules_layer_optimizer//python:rules_python.bzl", "py_image_layer")

py_image_layer(
    name = "app_layers",
    binary = ":app",
    strip_prefix = "my/package/app",
)
```

Outputs are `<name>_pip`, `<name>_source`, `<name>_interpreter`, and composite
`<name>`. Pass the separate outputs to optimizer groups. Paths are fixed to
`/app` and `/app.runfiles` so package layers are reusable across binaries.

Use rules_python's in-build interpreter and
`--@rules_python//python/config_settings:bootstrap_impl=script`; this avoids
needing a system Python just to launch the binary. Interpreter files come from
the binary's public PyRuntimeInfo provider. Source layers retain virtualenv
links, native extensions, runfiles metadata, and non-wheel data.

Wheel boundaries use rules_python's `pypi_name` tags. Package layers contain the
wheel-owned runtime files, including importable code and distribution metadata.
They follow upstream runfiles exclusions: for example, rules_python omits
`.dist-info/RECORD`. Tree-artifact wheel layouts are rejected explicitly.
Size hints use the largest wheel estimate for the distribution in the configured
uv lock, or caller-supplied positive estimates without a uv lock.

## Inference and assembly

`python:inference.bzl` supports both rule families for layer, APT, and environment
inference. See [configuration](../docs/configuration.md) for pip hub setup.

Both adapters' tars work with rules_oci and rules_img. See the
[aspect_rules_py example](../examples/python_image/BUILD.bazel),
[rules_python example](../examples/rules_python_image/BUILD.bazel), and
[standalone rules_python consumer](../e2e/rules_python/README.md).
[Compatibility](../docs/compatibility.md) lists tested upstream versions.
