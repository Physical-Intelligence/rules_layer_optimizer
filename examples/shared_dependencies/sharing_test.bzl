"""Check that two consumers reach exactly the same package artifact."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_layer_optimizer//layers:providers.bzl", "LayerTarsInfo", "SizeHintInfo")

def _sharing_test_impl(ctx):
    env = analysistest.begin(ctx)
    first = analysistest.target_under_test(env)
    second = ctx.attr.other
    asserts.equals(env, 1, len(first[LayerTarsInfo].tars))
    asserts.equals(env, first[LayerTarsInfo].tars, second[LayerTarsInfo].tars)
    asserts.equals(env, first[SizeHintInfo].sizes, second[SizeHintInfo].sizes)
    asserts.equals(env, [25335], first[SizeHintInfo].sizes.values())
    return analysistest.end(env)

sharing_test = analysistest.make(_sharing_test_impl, attrs = {"other": attr.label()})
