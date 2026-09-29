"""Verify the Python adapters compose generic layer and APT inference."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_layer_optimizer//layers:providers.bzl", "LayerTarsInfo")

def _inference_test_impl(ctx):
    env = analysistest.begin(ctx)
    layers = analysistest.target_under_test(env)[LayerTarsInfo].tars
    asserts.equals(env, ctx.attr.expected.files.to_list(), layers)
    asserts.equals(env, layers, ctx.attr.apt[LayerTarsInfo].tars)
    return analysistest.end(env)

inference_test = analysistest.make(_inference_test_impl, attrs = {"apt": attr.label(), "expected": attr.label()})
