# Dependency inference

The generic API matches exact Bazel labels through the root-configured graph
attributes. `layer_inference` registers triggers and layer producers;
`layer_inference_bundle` groups policies; `inferred_layers` selects matching
layers and preserves their size hints. It does not inspect Python wheel targets.

`env_inference`, `env_inference_bundle`, and `env_file` provide the same mechanism
for environment entries. `base_env` is applied first, matching entries next,
and `extra_env` last. PATH, LD_LIBRARY_PATH, and PYTHONPATH concatenate with
colons; XLA_FLAGS concatenates with spaces. Duplicate values for other variable
names fail analysis rather than silently overriding policy. `pythonpath_deps`
optionally contributes PyInfo import paths beneath the explicit runfiles root.

For logical pip-package triggers, load the matching rules from
`@rules_layer_optimizer//python:inference.bzl` instead. The adapter combines
Python identity collection with the generic rules. Configure the pip hub and
size hints as described in [configuration](../docs/configuration.md).

Inference bundles and policy belong to callers. There are no default production
mappings. The [smoke module](../e2e/smoke/BUILD.bazel) demonstrates generic
inference with a minimal dependency graph.
