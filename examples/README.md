# Examples

This separate Bazel module consumes only the public entrypoints through
`local_path_override`. Its dependencies and image policy belong to the consumer.
Run `bazel test //...` from this directory.

- [basic_layers](basic_layers/BUILD.bazel): flatten real tars and inspect the
  archive and optimization plan.
- [python_image](python_image/BUILD.bazel): create a Python OCI image with a
  digest-pinned Ubuntu base, explicitly packaged interpreter, shared wheel,
  source layer, and inferred environment. Source inspection tests build the
  image without requiring Docker.
- [shared_dependencies](shared_dependencies/BUILD.bazel): assert that two
  consumers reach the identical wheel artifact and selected-wheel size, and
  inspect the archive's package code and metadata.

The example's `.bazelrc` selects the uv dependency group from `pyproject.toml`.
The interpreter and base image target Linux x86-64.

To load and run the image locally when Docker is available:

```sh
bazel run //python_image:load
docker run --rm rules-layer-optimizer-example:local
```

This assembly is an example of caller-owned policy, not a supported `py_image`
API. It can be wrapped in a macro inside your own repository.
