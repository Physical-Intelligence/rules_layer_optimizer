# Minimum-version consumer

This module rebuilds [image_backends](../image_backends/README.md) at the oldest
supported rules_oci and rules_img versions. Source symlinks keep the image
targets identical. Bazel 8.7.0 is required because rules_oci 1.1.0 uses
`incompatible_use_toolchain_transition`, which Bazel 9 removed.

Run `bazel test //...` here. That compares layer digests across backends and
runs each image in Docker.

`single_version_override` pins the four main dependencies to their exact tested
floors. Those overrides belong only to this module. CI verifies the resolved
graph, so a transitive dependency cannot silently turn this into a test of
newer versions:

```sh
bazel mod graph --output=json > /tmp/layer_optimizer_minimum_graph.json
jq -e -f assert_versions.jq /tmp/layer_optimizer_minimum_graph.json
```

See [compatibility](../../docs/compatibility.md) for the support matrix.
