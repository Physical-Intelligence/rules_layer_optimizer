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

To enable Python package identities, add `pip_hub = "@packages//:defs.bzl"` to
`configure`, and add `inference.pip_size_hint(lock = "//:uv.lock")`. The Python
adapter currently uses aspect_rules_py 2.0.0-alpha.4. Configure its uv hub and
Python toolchain in the consumer module; see the complete examples module.

The selected wheel's filename chooses its compressed size from `uv.lock`.
For source-built wheels or indexes omitting sizes, provide positive byte values
as strings in `pip_size_hint(size_overrides = {"distribution_name": "1234"})`.
An override is a fallback, not a replacement for known selected-wheel metadata.

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
