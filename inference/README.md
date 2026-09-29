# Dependency inference

The generic API matches exact Bazel labels through the default or root-configured graph
attributes. `layer_inference` registers triggers and layer producers;
`layer_inference_bundle` groups those mappings. `inferred_layers` accepts only
bundles, selects matching layers, and preserves their size hints. It does not
inspect Python wheel targets.

`env_inference` registers environment entries and `env_inference_bundle` groups
them. `env_file` accepts only those bundles. `base_env` is applied first, matching entries next,
and `extra_env` last. PATH, LD_LIBRARY_PATH, and PYTHONPATH concatenate with
colons by default. The `env_separators` dictionary replaces that policy, e.g.
`env_separators = {"FLAGS": " "}` joins a caller-owned flag variable with spaces.
Duplicate variables without a configured separator fail analysis. `pythonpath_deps`
optionally contributes PyInfo import paths beneath the explicit runfiles root.

For logical pip-package triggers, load the matching rules from
`@rules_layer_optimizer//python:inference.bzl` instead. The adapter combines
Python identity collection with the generic rules. Configure the pip hub and
optional size hints as described in [configuration](../docs/configuration.md).

Inference bundles and policy belong to callers. There are no default production
mappings. The [distroless contract](../e2e/distroless/README.md) demonstrates generic
inference with a minimal dependency graph.

## API reference

All inference rules accept ordinary Bazel attributes such as `visibility` and
`tags`. Mapping macros also create a private `<name>_for_deps_test` that resolves
trigger labels without adding those dependencies to image analysis.

| API | Arguments and outputs |
| --- | --- |
| `layer_inference` | `name`, `for_deps`, `layers`, optional `for_keys = []`; registers a mapping and forwards layer files and size hints |
| `layer_inference_bundle` | `name`, `inferences`; groups layer mappings |
| `inferred_layers` | `name`, `deps`, `inferences` (`layer_inference_bundle` targets); emits matching ordered tars and size hints |
| `env_inference` | `name`, `env`, optional `for_deps = []`, `for_keys = []`; registers environment entries |
| `env_inference_bundle` | `name`, `inferences`; groups environment mappings |
| `env_file` | `name`, optional `deps`, `inferences` (`env_inference_bundle` targets), `base_env`, `extra_env`, `env_separators`, `pythonpath_deps`, `runfiles_root`; emits a `KEY=value` file |

`env_file` defaults to empty inputs, the path-variable separators described above,
and `runfiles_root = "/app.runfiles"`. `for_deps` entries match any visited label;
`for_keys` supports opaque identities supplied by adapters. The Python mapping macros derive `for_keys` from the configured pip hub;
callers supply `for_deps` rather than passing `for_keys` themselves.
