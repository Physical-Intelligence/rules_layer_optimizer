"""Conflicting environment values fail when no separator is configured."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _conflict_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "Unsupported merge of environment variable 'MODE'")
    return analysistest.end(env)

conflict_test = analysistest.make(_conflict_test_impl, expect_failure = True)
