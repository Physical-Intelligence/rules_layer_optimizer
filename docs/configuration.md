# Configuration

Consume the private checkout with `local_path_override`, as shown in
[examples/MODULE.bazel](../examples/MODULE.bazel). There is no registry release.

Layer planning and materialization can be loaded without configuring inference.
Consumers loading inference or Python layer production must configure exactly
one root-module tag:

```starlark
inference = use_extension(
    "@rules_layer_optimizer//inference:extensions.bzl",
    "oci_image_inference",
)
inference.configure(dependency_attributes = ["deps", "src", "srcs", "actual", "venv"])
use_repo(inference, "oci_image_inference_config")
```

To enable Python package identities, configure the hub used for inference labels:

- aspect_rules_py: `pip_hub = "@packages//:defs.bzl"`
- rules_python: `pip_hub = "@pip//:requirements.bzl"`

Configure exactly one `inference.pip_size_hint` tag. A uv lock works with either
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

APT hints come from caller-supplied rules_distroless v2 locks:

```starlark
inference.apt_size_hint(
    dependency_set = "debian",
    lock = "//:apt.lock.json",
    repository = "@my_debian_packages//:dpkg_status",
)
```

Repository labels respect Bzlmod mappings. The example smoke module deliberately
uses a differently named package repository and a small synthetic v2 lock.
See [compatibility](compatibility.md) before choosing an APT resolver version.
