# Configuration

`rules_layer_optimizer` involves multiple repository rules and aspect rules, so
there are a few pieces of configuration required outside of simply invoking
`optimized_layers`.

## Infer Apt packages

The need to include an apt package in an application's image is usually tied to
some other library target which runs code dependent on that apt package; the
problem is that Bazel doesn't know about this dependency.

First, declare the inferences once in a shared location:

```starlark
load("@rules_layer_optimizer//inference:defs.bzl", "layer_inference_bundle")
load("@rules_layer_optimizer//python:inference.bzl", "apt_inference")

# If a py_binary depends on this package, include the apt package.
apt_inference(
    name = "pyusb_apt",
    for_deps = ["@pip//pyusb"],
    packages = ["@noble//libusb-1.0-0-dev"],
)

# Bundle together multiple inferences, making them ready for `inferred_apt_deps`.
layer_inference_bundle(
    name = "apt_inferences",
    inferences = [":pyusb_apt"],
    visibility = ["//visibility:public"],
)
```

Then, consume the inferences with `inferred_apt_deps` to walk the application's
dependency graph and produce a target containing all of the inferred
dependencies:

```starlark
load("@rules_layer_optimizer//python:inference.bzl", "inferred_apt_deps")

inferred_apt_deps(
    name = "app_apt",
    # Extra packages to include regardless of inference
    base_packages = ["@noble//ca-certificates"],
    # Application entrypoint
    deps = [":app"],
    # The bundle of inferences from above
    inferences = ["//shared:apt_inferences"],
)
```

The result is a layer candidate. Group it with the binary's other tars in
`optimized_layers`. [APT layers](../apt/README.md) lists the remaining
arguments.

## Infer environment variables

Just like apt packages, the need to include an environment variable in an
application's image is usually tied to some other library target which runs
code dependent on that variable; the problem is that Bazel doesn't know about
this.

First, declare the inferences once in a shared location:

```starlark
load("@rules_layer_optimizer//inference:defs.bzl", "env_inference_bundle")
load("@rules_layer_optimizer//python:inference.bzl", "env_inference")

# If a py_binary depends on this package, include the environment variable.
env_inference(
    name = "colorama_env",
    env = {"COLORAMA_AVAILABLE": "1"},
    for_deps = ["@pip//colorama"],
)

env_inference_bundle(
    name = "env_inferences",
    inferences = [":colorama_env"],
    visibility = ["//visibility:public"],
)
```

Then, consume the inferences with `env_file` to walk the application's
dependency graph and produce a target containing all of the inferred
environment variables:

```starlark
load("@rules_layer_optimizer//python:inference.bzl", "env_file")

env_file(
    name = "app_env",
    # Extra variables to include regardless of inference
    base_env = {"PATH": "/usr/bin"},
    # Application entrypoint
    deps = [":app"],
    # The bundle of inferences from above
    inferences = ["//shared:env_inferences"],
)
```

The result is a `KEY=VALUE` file. Pass it to `oci_image` as `env` or to
`image_manifest` as `env_file`. [Dependency inference](../inference/README.md)
lists the remaining arguments.

## Repo-wide facts

Extension configuration must also be set in `MODULE.bazel`. The sections below
describe the options.

```starlark
inference = use_extension(
    "@rules_layer_optimizer//inference:extensions.bzl",
    "oci_image_inference",
)
use_repo(inference, "oci_image_inference_config")
```

### Which targets count as dependencies

Inference walks the binary and follows `deps`, `src`, `srcs`, `data`,
`actual`, and `venv`. That list matches a normal `py_binary`. Replace it when
a rule in your repo carries dependencies on some other attribute. There is one
`configure` tag:

```starlark
inference.configure(
    dependency_attributes = ["deps", "src", "srcs", "actual", "venv"],
)
```

### Which pip package a dependency is

Apt and environment mappings name a distribution, such as `@pip//colorama`.
The pip hub is what makes that label mean the same distribution for every
binary. Put `pip_hub` on the `configure` tag above. Leave
`dependency_attributes` unset to keep the default walk.

An aspect_rules_py hub exposes its distributions from `defs.bzl`:

```starlark
inference.configure(pip_hub = "@pip//:defs.bzl")
```

A rules_python hub exposes them from `requirements.bzl`:

```starlark
inference.configure(pip_hub = "@pip//:requirements.bzl")
```

Both arguments belong on that single tag when a repo needs a custom walk and a
hub:

```starlark
inference.configure(
    dependency_attributes = ["deps", "src", "srcs", "actual", "venv"],
    pip_hub = "@pip//:requirements.bzl",
)
```

With the hub set, mappings loaded from `python:inference.bzl` match a binary
that depends on the distribution. The exact-label rules in `apt:defs.bzl` and
`inference:defs.bzl` stay available when the trigger is an ordinary target.

### How large each pip package is

Name matching is enough to decide that a variable or an apt package belongs in
the image. A separate layer per distribution also needs a size, so the
optimizer can fold small wheels together and keep large ones alone. Declare
`pip_size_hint` once.

A `uv.lock` carries those sizes for either adapter:

```starlark
inference.pip_size_hint(lock = "//:uv.lock")
```

aspect_rules_py uses the size of the wheel it selected. rules_python uses the
largest wheel recorded for that distribution, because the selected filename is
not available from the `py_library`.

A requirements lock without `uv.lock` can supply positive byte counts as
strings:

```starlark
inference.pip_size_hint(size_overrides = {"colorama": "25335"})
```

The tag takes a `lock`, `size_overrides`, or both. Alongside a lock, an
override fills in a source-built package or a wheel the lock left unsized.

### How large each apt package is

Deb packages need the same kind of size before they can share a flattened
layer. Read it from a rules_distroless v2 lock. Repeat `apt_size_hint` for
every package repository:

```starlark
inference.apt_size_hint(
    dependency_set = "noble",
    lock = "//:apt.lock.json",
    repository = "@noble//:dpkg_status",
)
```

`dependency_set` selects that set inside the lock. `repository` is a label in
the set's repository, so a Bzlmod rename still resolves. These sizes are what
the apt layers above carry into the optimizer.
