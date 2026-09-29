"""Check that two consumers reach exactly the same package artifact."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_layer_optimizer//layers:providers.bzl", "LayerTarsInfo", "SizeHintInfo")

def _sharing_test_impl(ctx):
    env = analysistest.begin(ctx)
    first = analysistest.target_under_test(env)
    second = ctx.attr.other
    asserts.equals(env, ctx.attr.expected_count, len(first[LayerTarsInfo].tars))
    asserts.equals(env, first[LayerTarsInfo].tars, second[LayerTarsInfo].tars)
    asserts.equals(env, first[SizeHintInfo].sizes, second[SizeHintInfo].sizes)
    asserts.true(env, 25335 in first[SizeHintInfo].sizes.values())
    asserts.equals(env, ctx.attr.expected_count, len(first[SizeHintInfo].sizes))
    return analysistest.end(env)

sharing_test = analysistest.make(_sharing_test_impl, attrs = {"other": attr.label(), "expected_count": attr.int(default = 1)})
