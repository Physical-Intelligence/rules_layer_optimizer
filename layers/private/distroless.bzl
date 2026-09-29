"""rules_distroless materialization adapter for optimized OCI layers."""

load("@rules_distroless//distroless:defs.bzl", "flatten")
load("//layers/private:optimize_layers.bzl", "optimized_layers_plan")

_EMPTY_TAR = Label("//layers/private:empty_tar")

def _tar_inputs_impl(ctx):
    return [DefaultInfo(files = depset(transitive = [target[DefaultInfo].files for target in ctx.attr.tars]))]

_tar_inputs = rule(
    implementation = _tar_inputs_impl,
    attrs = {"tars": attr.label_list(allow_files = True)},
)

def optimized_layers(
        name,
        groups,
        layer_budget,
        size_bytes_threshold,
        compress = "zstd",
        flatten_all = False,
        tags = [],
        visibility = None):
    """Plans layers and materializes flat groups with rules_distroless.

    Args:
        name: Name of the generated target or test suite.
        groups: Ordered layer_group entries.
        layer_budget: Maximum number of generated layers.
        size_bytes_threshold: Minimum size hint in bytes for an individual layer.
        compress: Archive compression algorithm.
        flatten_all: Whether to combine every input into one archive.
        tags: Tags for generated targets.
        visibility: Visibility of the result and optimization plan.
    """
    plan = optimized_layers_plan(
        name = name,
        groups = groups,
        layer_budget = layer_budget,
        size_bytes_threshold = size_bytes_threshold,
        flatten_all = flatten_all,
        tags = tags,
        visibility = visibility,
    )

    if flatten_all:
        flatten(
            name = name,
            tars = [plan.all_tars],
            deduplicate = True,
            compress = compress,
            tags = tags,
            visibility = visibility,
        )
        return

    srcs = []
    for group in plan.groups:
        srcs.append(group.individual_tars)
        if group.flat_tars:
            flat_layer = "{}_{}_flat_layer".format(name, group.name)
            flat_inputs = flat_layer + "_inputs"
            _tar_inputs(
                name = flat_inputs,
                tars = [
                    group.flat_tars,
                    _EMPTY_TAR,
                ],
                tags = tags,
                visibility = ["//visibility:private"],
            )
            flatten(
                name = flat_layer,
                tars = [flat_inputs],
                deduplicate = True,
                compress = compress,
                tags = tags,
                visibility = ["//visibility:private"],
            )
            srcs.append(flat_layer)

    native.filegroup(
        name = name,
        srcs = srcs,
        tags = tags,
        visibility = visibility,
    )
