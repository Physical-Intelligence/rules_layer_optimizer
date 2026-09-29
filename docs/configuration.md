# Configuration

See the [quickstart](../README.md#get-started) for installation and
[release preparation](../.bcr/README.md) for packaged installation.

Layer planning, materialization, and generic inference work without root-module
configuration. Inference traverses `deps`, `src`, `srcs`, `data`, `actual`, and
`venv` by default. To replace that list, optionally configure the extension:

```starlark
inference = use_extension(
    "@rules_layer_optimizer//inference:extensions.bzl",
    "oci_image_inference",
)
inference.configure(dependency_attributes = ["deps", "src", "srcs", "actual", "venv"])
use_repo(inference, "oci_image_inference_config")
```

To enable Python package identities, add `pip_hub` to a `configure` tag.
`dependency_attributes` can be omitted to keep the defaults:

- aspect_rules_py: `pip_hub = "@packages//:defs.bzl"`
- rules_python: `pip_hub = "@pip//:requirements.bzl"`

Package identity inference does not require size hints. Package **layer production**
requires positive size estimates; configure at most one `inference.pip_size_hint`
tag when producing package layers. A uv lock works with either
adapter: `inference.pip_size_hint(lock = "//:uv.lock")`. aspect_rules_py selects
an exact wheel size by filename. rules_python uses the largest available wheel
size for each distribution, since its py_library does not expose that filename.

Consumers using requirements.txt without uv can provide estimates directly:

```starlark
inference.pip_size_hint(size_overrides = {"colorama": "25335"})
```

Values must be positive byte counts, supplied as strings. With a uv lock,
overrides are limited to source-built or unsized packages and act as fallbacks
for exact wheel sizes. Without a lock, they supply all package size estimates.
See the [standalone rules_python module](../e2e/rules_python/MODULE.bazel).

The [APT adapter](../apt/README.md) takes hints from caller-supplied
rules_distroless v2 locks:

```starlark
inference.apt_size_hint(
    dependency_set = "debian",
    lock = "//:apt.lock.json",
    repository = "@my_debian_packages//:dpkg_status",
)
```

Repository labels respect Bzlmod mappings. The example smoke module deliberately
uses a differently named package repository and a small synthetic v2 lock.
See [APT layers](../apt/README.md) for resolver requirements.

The root may supply at most one `configure` tag; other modules cannot override
its policy. Size hints may be supplied without a pip hub, and a pip hub may be
supplied without size hints. `apt_size_hint` tags can be repeated for multiple
package repositories. Each requires `dependency_set`, `lock`, and `repository`.
