"""External-consumer checks for APT metadata and conflict handling."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_layer_optimizer//layers:providers.bzl", "LayerTarsInfo", "SizeHintInfo")

def _apt_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    tars = target[LayerTarsInfo].tars
    asserts.equals(env, 1, len(tars))
    asserts.equals(env, {tars[0]: 42}, target[SizeHintInfo].sizes)
    return analysistest.end(env)

apt_test = analysistest.make(_apt_test_impl)

def _conflict_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "Unsupported merge of environment variable 'MODE'")
    return analysistest.end(env)

conflict_test = analysistest.make(_conflict_test_impl, expect_failure = True)
