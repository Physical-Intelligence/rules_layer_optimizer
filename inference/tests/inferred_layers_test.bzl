"""Tests for generic dependency-inferred OCI layers."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//inference/private:inferred_layers.bzl", "inferred_layers", "layer_inference", "layer_inference_bundle")

# buildifier: disable=bzl-visibility
load("//layers/private:layer_groups.bzl", "LayerTarsInfo", "SizeHintInfo")

def inferred_layers_test_suite(name):
    """Declare generic layer inference subjects and their analysis test.

    Args:
        name: Name of the generated target or test suite.
    """
    native.filegroup(name = "layer_inference_trigger")
    native.filegroup(name = "unmatched_layer_inference_trigger")
    _layer_stub(name = "inferred_layer_match")
    _layer_stub(name = "inferred_layer_no_match")
    _multi_output_layer_stub(name = "selected_layer_outputs", provide_layer_tars = True)
    _multi_output_layer_stub(
        name = "ambiguous_layer_outputs",
        provide_layer_tars = False,
        tags = ["manual"],
    )
    _size_hint_wrapper(name = "inferred_layer_size_a", src = ":inferred_layer_match", size_bytes = 1)
    _size_hint_wrapper(name = "inferred_layer_size_b", src = ":inferred_layer_match", size_bytes = 2)

    layer_inference(
        name = "matched_layer_inference",
        for_deps = ["//inference/tests:layer_inference_trigger"],
        layers = [":inferred_layer_match"],
    )
    layer_inference(
        name = "unmatched_layer_inference",
        for_deps = ["//inference/tests:unmatched_layer_inference_trigger"],
        layers = [":inferred_layer_no_match"],
    )
    layer_inference(
        name = "pip_layer_inference",
        for_deps = [":layer_inference_trigger"],
        layers = [":selected_layer_outputs"],
    )
    layer_inference_bundle(
        name = "layer_inference_test_bundle",
        inferences = [
            ":matched_layer_inference",
            ":unmatched_layer_inference",
            ":pip_layer_inference",
        ],
    )
    inferred_layers(
        name = "inferred_layers_subject",
        deps = [":layer_inference_trigger"],
        inferences = [":layer_inference_test_bundle"],
    )
    _inferred_layers_test(
        name = name,
        target_under_test = ":inferred_layers_subject",
    )

    layer_inference(
        name = "conflicting_layer_inference",
        for_deps = ["//inference/tests:layer_inference_trigger"],
        layers = [
            ":inferred_layer_size_a",
            ":inferred_layer_size_b",
        ],
        tags = ["manual"],
    )
    _expect_failure_test(
        name = "conflicting_layer_inference_test",
        target_under_test = ":conflicting_layer_inference",
        message = "provides conflicting size hints 1 and 2",
    )

    layer_inference(
        name = "ambiguous_layer_inference",
        for_deps = ["//inference/tests:layer_inference_trigger"],
        layers = [":ambiguous_layer_outputs"],
        tags = ["manual"],
    )
    _expect_failure_test(
        name = "ambiguous_layer_inference_test",
        target_under_test = ":ambiguous_layer_inference",
        message = "has multiple default outputs; provide LayerTarsInfo",
    )

def _layer_stub_impl(ctx):
    output = ctx.actions.declare_file(ctx.label.name + ".tar")
    ctx.actions.write(output, "")
    return [
        DefaultInfo(files = depset([output])),
        SizeHintInfo(sizes = {output: 42}),
    ]

_layer_stub = rule(implementation = _layer_stub_impl)

def _multi_output_layer_stub_impl(ctx):
    selected = ctx.actions.declare_file(ctx.label.name + ".tar")
    metadata = ctx.actions.declare_file(ctx.label.name + ".metadata")
    ctx.actions.write(selected, "")
    ctx.actions.write(metadata, "")
    providers = [DefaultInfo(files = depset([selected, metadata]))]
    if ctx.attr.provide_layer_tars:
        providers.extend([
            LayerTarsInfo(tars = [selected]),
            SizeHintInfo(sizes = {selected: 84}),
        ])
    return providers

_multi_output_layer_stub = rule(
    implementation = _multi_output_layer_stub_impl,
    attrs = {"provide_layer_tars": attr.bool(mandatory = True)},
)

def _size_hint_wrapper_impl(ctx):
    file = ctx.file.src
    return [
        DefaultInfo(files = depset([file])),
        SizeHintInfo(sizes = {file: ctx.attr.size_bytes}),
    ]

_size_hint_wrapper = rule(
    implementation = _size_hint_wrapper_impl,
    attrs = {
        "size_bytes": attr.int(mandatory = True),
        "src": attr.label(allow_single_file = True, mandatory = True),
    },
)

def _inferred_layers_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    tars = target[LayerTarsInfo].tars

    asserts.equals(env, ["inferred_layer_match.tar", "selected_layer_outputs.tar"], [tar.basename for tar in tars])
    asserts.equals(env, tars, target[DefaultInfo].files.to_list())
    asserts.equals(env, {tars[0]: 42, tars[1]: 84}, target[SizeHintInfo].sizes)
    return analysistest.end(env)

_inferred_layers_test = analysistest.make(_inferred_layers_test_impl)

def _expect_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.message)
    return analysistest.end(env)

_expect_failure_test = analysistest.make(
    _expect_failure_test_impl,
    attrs = {"message": attr.string(mandatory = True)},
    expect_failure = True,
)
