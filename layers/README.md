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

See [the layer plan check](../e2e/layer_plan/BUILD.bazel).

Subtract base-image layers from the desired runtime limit when choosing
`layer_budget`. Size hints estimate input package sizes, not output archive sizes.
Changing a package in an overflow layer rebuilds that shared layer.

## Filesystem ordering contract

Only put inputs that are safe to reorder in `overflow = "flatten"` groups.
Size sorting and budget spill can change their order, and flattening combines
multiple inputs into a single filesystem layer. Different contents at the same
path, file/directory replacements, and symlink replacements are order-sensitive.
The optimizer does not inspect archives to detect these conflicts.

Keep order-sensitive archives in `overflow = "individual"` groups, in their
required application order. These groups preserve input order and each archive
stays a separate layer. They must not carry size hints. Group order is also
preserved, so an individual application/override group can follow package groups.

OCI whiteouts (`.wh.<name>` and `.wh..wh..opq`) delete entries from lower layers.
They are supported only in unflattened individual groups: merging or reordering
them can change which entries they delete. Do not use `flatten_all = True` for
whiteouts or other order-sensitive inputs; it bypasses individual-group boundaries.
The [archive regression test](tests/order_test.bzl) exercises overwrites, file
whiteouts, and opaque-directory whiteouts through ordered optimizer output.

## Image backends

Pass the same optimized tar target directly to either backend:

```starlark
oci_image(name = "oci", tars = [":layers"], ...)
image_manifest(name = "img", layers = [":layers"], ...)
```

Load `oci_image` from `@rules_oci//oci:defs.bzl`, or `image_manifest` from
`@rules_img//img:image.bzl`. Inferred environment files go to `env` for rules_oci
and `env_file` for rules_img. The [image backend checks](../e2e/image_backends/README.md) assemble runnable images with both;
base-image selection and backend dependencies remain consumer configuration.

## API reference

| API | Arguments |
| --- | --- |
| `layer_group` | Required `name`, ordered `targets`; `overflow = "individual"` or `"flatten"` |
| `optimized_layers_plan` | Required `name`, `groups`, `layer_budget`, `size_bytes_threshold`; optional `flatten_all = False`, `tags = []`, `visibility = None` |
| `optimized_layers` | The same arguments, plus `compress = "zstd"` |

`optimized_layers_plan` returns a struct with `all_tars`, `optimization_plan`,
`flatten_all`, and ordered `groups`. Each group has `name`, `individual_tars`, and
`flat_tars` (or `None`). These are target names in the calling package. Public
outputs include `<name>_all_tars`, `<name>_optimization_plan`, and
`<name>_<group>_individual_tars` / `<name>_<group>_flat_tars`.

`optimized_layers` creates `<name>` containing the final ordered archives and
exposes the same plan outputs. Materialization helpers remain private.
`visibility` applies to public outputs; `None` uses the caller's package default.
`MAX_DOCKER_LAYERS` is an available convenience constant; callers still supply
the generated-layer budget explicitly.
