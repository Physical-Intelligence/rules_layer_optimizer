# Layer optimization

`layer_group` defines ordered groups of tar targets. `optimized_layers_plan`
selects layers without choosing a materialization backend. `optimized_layers`
in `layers:distroless.bzl` materializes that plan with rules_distroless.

```starlark
load("@rules_layer_optimizer//layers:defs.bzl", "layer_group")
load("@rules_layer_optimizer//layers:distroless.bzl", "optimized_layers")

optimized_layers(
    name = "layers",
    groups = [layer_group(name = "packages", targets = [":package_tars"], overflow = "flatten")],
    layer_budget = 20,
    size_bytes_threshold = 1024 * 1024,
)
```

Both the budget and threshold are explicit. Groups default to `individual`:
every tar stays separate, and size hints are rejected. `flatten` groups reserve
one overflow layer each, then keep the largest size-eligible candidates within
the remaining shared budget. Unsized and small candidates go into overflow.
Ordering is deterministic; candidates use size, group name, and path as sort keys.

Producers should expose `LayerTarsInfo(tars = [...])` and optionally
`SizeHintInfo(sizes = {file: positive_bytes})` from `layers:providers.bzl`.
A single `DefaultInfo` output is also accepted. Ambiguous multiple outputs,
conflicting hints, and cross-group duplication fail analysis.

`<name>_optimization_plan` is a versioned JSON filegroup containing the policy,
ordered groups, output layers, input sizes, and placement reasons. Each flatten
group emits an archive, even when its overflow is empty. `flatten_all = True`
combines everything into one archive. Base-image layers are outside this budget.

See [the runnable example](../examples/basic_layers/BUILD.bazel).

## Image backends

Pass the same optimized tar target directly to either backend:

```starlark
oci_image(name = "oci", tars = [":layers"], ...)
image_manifest(name = "img", layers = [":layers"], ...)
```

Load `oci_image` from `@rules_oci//oci:defs.bzl`, or `image_manifest` from
`@rules_img//img:image.bzl`. Inferred environment files go to `env` for rules_oci
and `env_file` for rules_img. The examples assemble runnable images with both;
base-image selection and backend dependencies remain consumer configuration.
