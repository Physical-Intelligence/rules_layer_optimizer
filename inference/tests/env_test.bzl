"""Environment inference and merge contract tests."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//inference/private:env.bzl", "merge_env")

def _merge_test_impl(ctx):
    env = unittest.begin(ctx)
    base = {"PATH": "/bin", "PYTHONPATH": "/lib", "MODE": "test"}
    merged = merge_env(base, {"PATH": "/tools", "PYTHONPATH": "/extra"})
    asserts.equals(env, {"PATH": "/bin:/tools", "PYTHONPATH": "/lib:/extra", "MODE": "test"}, merged)
    asserts.equals(env, {"PATH": "/bin", "PYTHONPATH": "/lib", "MODE": "test"}, base)
    asserts.equals(env, {"FLAGS": "--one --two"}, merge_env({"FLAGS": "--one"}, {"FLAGS": "--two"}, separators = {"FLAGS": " "}))
    return unittest.end(env)

merge_test = unittest.make(_merge_test_impl)
