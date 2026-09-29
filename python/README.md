# Python layers

`python:defs.bzl` exports `py_image_layer`, `pip_layer_reducer`,
`source_dep_bucket`, and `source_dep_match`. There is no image-assembly macro.

`pip_layer_reducer(deps = [...])` collects one tar per selected wheel, preserving
its installed site-packages payload and exposing LayerTarsInfo and SizeHintInfo.
Tar actions belong to the wheel target, so different binaries selecting the
same wheel share the same artifact. Reaching distinct wheels for one normalized
distribution is rejected. Size selection uses the actual configured wheel.

`py_image_layer` additionally splits binary runfiles into source, source
buckets, and PyO3 artifacts. Callers must supply `binary`, `interpreter_tar`,
`python_toolchain`, and `source_dep_buckets` (an empty list is valid). Use
`root = "/app"` and a `strip_prefix` corresponding to the binary label's
`package/name`. The interpreter tar must install under the same runfiles
repository path used by the binary.

Public output targets are `<name>_pip`, `<name>_source`, `<name>_source_deps`,
`<name>_pyo3`, and the composite `<name>` target. `<name>_no_src` and
`<name>_only_src` provide coarse partitions. Combine these using the generic
optimizer and your chosen image backend.

See the [Python example](../examples/python_image/BUILD.bazel) for complete
consumer-owned interpreter, environment, and OCI assembly configuration.
[Compatibility](../docs/compatibility.md) describes the private upstream provider
boundary and fixed runfiles layout.
