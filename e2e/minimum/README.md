# Minimum-version consumer

This module tests the oldest supported combination with the same fixtures as
[the current-version examples](../../examples/README.md). Source symlinks keep
package-sharing, source isolation, inferred environment, metadata, backend
layer equivalence, and Docker runtime coverage identical at both endpoints.

Run `bazel test //...` here. CI also runs all four image combinations in Docker.

`single_version_override` pins all four main dependencies to their exact tested
floors. Those overrides belong only to this test consumer. CI verifies the
resolved graph, so a transitive dependency cannot silently turn this into a test
of newer versions:

```sh
bazel mod graph --output=json > /tmp/layer_optimizer_minimum_graph.json
jq -e -f assert_versions.jq /tmp/layer_optimizer_minimum_graph.json
```

See [compatibility](../../docs/compatibility.md) for the support matrix,
version-selection policy, and reasons earlier versions are outside support.

This legacy combination uses Bazel 8.7.0: rules_oci 1.1.0 uses
`incompatible_use_toolchain_transition`, removed in Bazel 9. The root and
current-version consumers use Bazel 9.2.0.
