"""Tests for the generic optimize_layers API."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//layers/private:distroless.bzl", "optimized_layers")
load("//layers/private:layer_groups.bzl", "LayerTarsInfo", "SizeHintInfo", "layer_group")

def _sized_tar_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".tar")
    ctx.actions.write(out, "")
    providers = [
        DefaultInfo(files = depset([out])),
        LayerTarsInfo(tars = [out]),
    ]
    if ctx.attr.size_bytes >= 0:
        providers.append(SizeHintInfo(sizes = {out: ctx.attr.size_bytes}))
    return providers

sized_tar = rule(
    implementation = _sized_tar_impl,
    attrs = {"size_bytes": attr.int(default = -1)},
)

def _size_hint_wrapper_impl(ctx):
    file = ctx.file.src
    return [
        DefaultInfo(files = depset([file])),
        LayerTarsInfo(tars = [file]),
        SizeHintInfo(sizes = {file: ctx.attr.size_bytes}),
    ]

size_hint_wrapper = rule(
    implementation = _size_hint_wrapper_impl,
    attrs = {
        "size_bytes": attr.int(mandatory = True),
        "src": attr.label(allow_single_file = True, mandatory = True),
    },
)

def _invalid_member_hint_impl(ctx):
    layer = ctx.actions.declare_file(ctx.label.name + ".tar")
    other = ctx.actions.declare_file(ctx.label.name + "_metadata.txt")
    ctx.actions.write(layer, "")
    ctx.actions.write(other, "")
    return [
        DefaultInfo(files = depset([layer, other])),
        LayerTarsInfo(tars = [layer]),
        SizeHintInfo(sizes = {other: 1}),
    ]

invalid_member_hint = rule(implementation = _invalid_member_hint_impl)

def _multiple_outputs_impl(ctx):
    outputs = [ctx.actions.declare_file(ctx.label.name + suffix) for suffix in ["_one.tar", "_two.tar"]]
    for output in outputs:
        ctx.actions.write(output, "")
    return [DefaultInfo(files = depset(outputs))]

multiple_outputs = rule(implementation = _multiple_outputs_impl)

def _optimized_layers_test_impl(ctx):
    env = analysistest.begin(ctx)
    layers = ctx.attr.target_under_test[DefaultInfo].files.to_list()
    names = [layer.basename for layer in layers]

    asserts.true(
        env,
        len(layers) <= ctx.attr.layer_budget,
        "Layer count {} exceeds budget {}: {}".format(len(layers), ctx.attr.layer_budget, names),
    )
    if ctx.attr.flatten_all:
        asserts.equals(env, 1, len(layers), "Expected one flattened layer")
    for group in ctx.attr.expected_flat_groups:
        asserts.true(
            env,
            any(["_{}_flat_layer.tar".format(group) in name for name in names]),
            "Expected a flat layer for {}: {}".format(group, names),
        )
    for filename in ctx.attr.expected_individual:
        asserts.true(env, filename in names, "Expected individual layer {}: {}".format(filename, names))
    for filename in ctx.attr.expected_flattened:
        asserts.false(env, filename in names, "Expected {} to be flattened: {}".format(filename, names))

    return analysistest.end(env)

optimized_layers_test = analysistest.make(
    _optimized_layers_test_impl,
    attrs = {
        "expected_flat_groups": attr.string_list(),
        "expected_flattened": attr.string_list(),
        "expected_individual": attr.string_list(),
        "layer_budget": attr.int(mandatory = True),
        "flatten_all": attr.bool(),
    },
)

def _expect_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.message)
    return analysistest.end(env)

expect_failure_test = analysistest.make(
    _expect_failure_test_impl,
    attrs = {"message": attr.string(mandatory = True)},
    expect_failure = True,
)

def _optimization_plan_test_impl(ctx):
    env = analysistest.begin(ctx)
    files = ctx.attr.target_under_test[DefaultInfo].files.to_list()
    asserts.equals(env, 1, len(files))
    asserts.true(env, files[0].basename.endswith("_optimization_plan.json"))
    return analysistest.end(env)

optimization_plan_test = analysistest.make(_optimization_plan_test_impl)

def optimize_layers_test_suite(name):
    """Declares tests for thresholding, budgeting, validation, and diagnostics.

    Args:
        name: Name of the generated target or test suite.
    """
    sized_tar(name = "heavy", size_bytes = 8 * 1024 * 1024)
    sized_tar(name = "medium", size_bytes = 4 * 1024 * 1024)
    sized_tar(name = "light", size_bytes = 4)
    sized_tar(name = "unsized")
    sized_tar(name = "application")
    invalid_member_hint(name = "invalid_member_hint")
    multiple_outputs(name = "multiple_outputs")
    size_hint_wrapper(name = "heavy_size_a", src = ":heavy", size_bytes = 1)
    size_hint_wrapper(name = "heavy_size_b", src = ":heavy", size_bytes = 2)
    size_hint_wrapper(name = "heavy_size_c", src = ":heavy", size_bytes = 1)

    optimized_layers(
        name = "threshold_subject",
        groups = [
            layer_group(
                name = "packages",
                targets = [":heavy", ":light", ":unsized"],
                overflow = "flatten",
            ),
            layer_group(name = "application", targets = [":application"]),
        ],
        layer_budget = 4,
        size_bytes_threshold = 1024,
    )
    optimized_layers_test(
        name = "threshold_test",
        target_under_test = ":threshold_subject",
        expected_flat_groups = ["packages"],
        expected_flattened = ["light.tar", "unsized.tar"],
        expected_individual = ["application.tar", "heavy.tar"],
        layer_budget = 4,
    )

    optimized_layers(
        name = "spill_subject",
        groups = [
            layer_group(
                name = "packages",
                targets = [":heavy", ":medium"],
                overflow = "flatten",
            ),
        ],
        layer_budget = 2,
        size_bytes_threshold = 1024,
    )
    optimized_layers_test(
        name = "spill_test",
        target_under_test = ":spill_subject",
        expected_flat_groups = ["packages"],
        expected_flattened = ["medium.tar"],
        expected_individual = ["heavy.tar"],
        layer_budget = 2,
    )

    optimized_layers(
        name = "no_optimizations_subject",
        groups = [layer_group(name = "application", targets = [":heavy", ":medium"])],
        flatten_all = True,
        layer_budget = 4,
        size_bytes_threshold = 1024,
    )
    optimized_layers_test(
        name = "no_optimizations_test",
        target_under_test = ":no_optimizations_subject",
        layer_budget = 4,
        flatten_all = True,
    )

    optimized_layers(
        name = "insufficient_budget_subject",
        groups = [],
        layer_budget = 1,
        size_bytes_threshold = 1024,
        tags = ["manual"],
    )
    expect_failure_test(
        name = "insufficient_budget_test",
        target_under_test = ":insufficient_budget_subject_all_tars",
        message = "optimized layer grouping requires at least 2 generated layers; got 1",
    )

    optimized_layers(
        name = "negative_threshold_subject",
        groups = [],
        layer_budget = 4,
        size_bytes_threshold = -1,
        tags = ["manual"],
    )
    expect_failure_test(
        name = "negative_threshold_test",
        target_under_test = ":negative_threshold_subject_all_tars",
        message = "size_bytes_threshold must be non-negative, got -1",
    )

    optimized_layers(
        name = "duplicate_group_subject",
        groups = [
            layer_group(name = "first", targets = [":heavy_size_a"], overflow = "flatten"),
            layer_group(name = "second", targets = [":heavy_size_c"], overflow = "flatten"),
        ],
        layer_budget = 4,
        size_bytes_threshold = 1024,
        tags = ["manual"],
    )
    expect_failure_test(
        name = "duplicate_group_test",
        target_under_test = ":duplicate_group_subject_all_tars",
        message = "belongs to both 'first' and 'second'",
    )

    optimized_layers(
        name = "conflicting_size_subject",
        groups = [layer_group(
            name = "packages",
            targets = [":heavy_size_a", ":heavy_size_b"],
            overflow = "flatten",
        )],
        layer_budget = 4,
        size_bytes_threshold = 1024,
        tags = ["manual"],
    )
    expect_failure_test(
        name = "conflicting_size_test",
        target_under_test = ":conflicting_size_subject_all_tars",
        message = "has conflicting size hints 1 and 2",
    )

    size_hint_wrapper(name = "zero_size", src = ":medium", size_bytes = 0)
    optimized_layers(
        name = "zero_size_subject",
        groups = [layer_group(name = "packages", targets = [":zero_size"], overflow = "flatten")],
        layer_budget = 4,
        size_bytes_threshold = 1024,
        tags = ["manual"],
    )
    expect_failure_test(
        name = "zero_size_test",
        target_under_test = ":zero_size_subject_all_tars",
        message = "provides a non-positive size hint 0",
    )

    optimized_layers(
        name = "invalid_member_hint_subject",
        groups = [layer_group(name = "packages", targets = [":invalid_member_hint"], overflow = "flatten")],
        layer_budget = 4,
        size_bytes_threshold = 1024,
        tags = ["manual"],
    )
    expect_failure_test(
        name = "invalid_member_hint_test",
        target_under_test = ":invalid_member_hint_subject_all_tars",
        message = "which is not in its layer tar files",
    )

    optimized_layers(
        name = "multiple_outputs_subject",
        groups = [layer_group(name = "application", targets = [":multiple_outputs"])],
        layer_budget = 4,
        size_bytes_threshold = 1024,
        tags = ["manual"],
    )
    expect_failure_test(
        name = "multiple_outputs_test",
        target_under_test = ":multiple_outputs_subject_all_tars",
        message = "has multiple default outputs; provide LayerTarsInfo",
    )

    optimized_layers(
        name = "sized_individual_subject",
        groups = [layer_group(name = "application", targets = [":heavy"])],
        layer_budget = 4,
        size_bytes_threshold = 1024,
        tags = ["manual"],
    )
    expect_failure_test(
        name = "sized_individual_test",
        target_under_test = ":sized_individual_subject_all_tars",
        message = "uses overflow='individual' but received SizeHintInfo",
    )

    optimization_plan_test(
        name = "optimization_plan_test",
        target_under_test = ":threshold_subject_optimization_plan",
    )

    native.test_suite(
        name = name,
        tests = [
            ":conflicting_size_test",
            ":duplicate_group_test",
            ":insufficient_budget_test",
            ":invalid_member_hint_test",
            ":multiple_outputs_test",
            ":negative_threshold_test",
            ":no_optimizations_test",
            ":optimization_plan_test",
            ":sized_individual_test",
            ":spill_test",
            ":threshold_test",
            ":zero_size_test",
        ],
    )
