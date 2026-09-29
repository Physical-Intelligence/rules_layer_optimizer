# Python layers

Choose the entrypoint matching your Python rules:

| Entrypoint | Layer outputs |
| --- | --- |
| `python:aspect_rules_py.bzl` | Pip, caller-defined source layers, caller-supplied interpreter |
| `python:rules_python.bzl` | Pip, source, interpreter selected by the binary |

`python:defs.bzl` remains an alias for the aspect_rules_py adapter. Both adapters
export `py_image_layer` and `pip_layer_reducer`; image assembly belongs to callers.

`pip_layer_reducer(deps = [...])` collects one tar per distribution and exposes
LayerTarsInfo and SizeHintInfo. Actions belong to the wheel target, so binaries
selecting the same wheel reuse the same artifact. Reaching distinct wheels for
one normalized distribution is rejected. Both adapters share collection,
ordering, conflict checks, inference, and virtualenv symlink preservation.

## aspect_rules_py

`py_image_layer` splits binary runfiles into reusable package layers and source
layers. Supply a tar containing the interpreter at the binary's runfiles path.
Native extensions stay with their owning package or source files.

```starlark
load("@rules_layer_optimizer//python:aspect_rules_py.bzl", "py_image_layer")

py_image_layer(
    name = "app_layers",
    binary = ":app",
    interpreter_tar = ":interpreter",
    python_toolchain = "@python_interpreters//:current_py_toolchain",
    strip_prefix = "my/package/app",
    source_layers = {
        "assets": ["/assets/"],
        "native": ["[.]so$"],
    },
)
```

Source patterns are AWK extended regular expressions matched against the normalized,
mtree-escaped path (for example `./app.runfiles/_main/pkg/data`). Exclusions run
first, then `source_layers` in declaration order: the first matching layer owns
an entry. Unmatched entries remain in the source layer. A directory pattern does
not implicitly select its descendants; use a prefix pattern such as `/assets/`.
Each declared source layer produces a tar even when empty. The caller chooses
whether to declare a layer; there is no separate presence-matching language.

Interpreter and package runfiles are handled by their dedicated producers.
`exclude_patterns` omits other entries supplied in separate caller-owned tars;
callers must include those tars when assembling the image.

| Argument | Meaning / default |
| --- | --- |
| `name`, `binary` | Required output prefix and aspect_rules_py binary |
| `interpreter_tar` | Required interpreter archive matching the binary's runfiles layout |
| `python_toolchain` | Required exec-config target exposing `PYTHON3` and interpreter files |
| `strip_prefix` | Required **literal** binary path, e.g. `my/package/app` |
| `source_layers` | Ordered layer-name → path-regex-list mapping; default `{}` |
| `exclude_patterns` | Paths packaged separately by the caller; default `[]` |
| `compress` | Source tar compression; default `"zstd"` |
| `tar_args` | Additional source tar arguments; default `[]` |
| `compute_unused_inputs` | Passed to the tar rule; default `0` |
| Common attributes | `visibility`, `tags`, `testonly`, compatibility constraints, etc. |

Layer names contain letters, numbers, or underscores; `deps` is reserved.
Outputs are `<name>_pip`, `<name>_interpreter`, `<name>_source`, and
`<name>_source_<layer>` for each source layer. `<name>_source_deps` collects the
custom source layers; `<name>` collects pip, interpreter, custom source, and
remaining source layers in that order. Intermediate targets are private.
All generated targets preserve common attributes, including caller-supplied tags.

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

| Argument | Meaning / default |
| --- | --- |
| `name`, `binary` | Required output prefix and rules_python binary |
| `strip_prefix` | Required literal binary path, e.g. `my/package/app` |
| `compress` | Source and interpreter tar compression; default `"gzip"` |
| Common attributes | `visibility`, `tags`, `testonly`, compatibility constraints, etc. |

Both adapters keep package tars reusable at `/app.runfiles`; the binary entrypoint
is `/app`. Package compression is fixed per adapter (zstd for aspect_rules_py,
gzip for rules_python) and is independent of `compress`.

`pip_layer_reducer(name, deps = [...], **kwargs)` is also available from either
entrypoint when only reusable package tars are needed. It collects unique wheel
artifacts in descending size order and exposes `LayerTarsInfo` and `SizeHintInfo`.

## Inference and assembly

`python:inference.bzl` supports both rule families for layer, APT, and environment
inference. See [configuration](../docs/configuration.md) for pip hub setup.

Both adapters' tars work with rules_oci and rules_img. See the
[aspect_rules_py example](../examples/python_image/BUILD.bazel),
[rules_python example](../examples/rules_python_image/BUILD.bazel), and
[standalone rules_python consumer](../e2e/rules_python/README.md).
[Compatibility](../docs/compatibility.md) lists tested upstream versions.
