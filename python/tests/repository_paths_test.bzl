"""Tests for canonical external-repository path helpers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//python/private:repository_paths.bzl", "module_extension_repo_pattern")

def _repository_paths_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        "aspect_rules_py[+~][+~]uv[+~]whl_install__",
        module_extension_repo_pattern("aspect_rules_py", "uv", "whl_install__"),
    )

    return unittest.end(env)

repository_paths_test = unittest.make(_repository_paths_test_impl)

def repository_paths_test_suite(name):
    repository_paths_test(name = name)
