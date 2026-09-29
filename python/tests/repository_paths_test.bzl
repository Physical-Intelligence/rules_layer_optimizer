"""Tests for canonical external-repository path helpers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//python/private:repository_paths.bzl", "module_extension_repo_pattern", "repository_rule_repo_in_path", "repository_rule_repo_pattern")

def _repository_paths_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        "aspect_rules_py[+~][+~]uv[+~]whl_install__",
        module_extension_repo_pattern("aspect_rules_py", "uv", "whl_install__"),
    )
    asserts.equals(env, "[+~]_repo_rules[+~]", repository_rule_repo_pattern("_repo_rules"))
    asserts.true(env, repository_rule_repo_in_path("external/+_repo_rules+example/file", "_repo_rules"))
    asserts.true(env, repository_rule_repo_in_path("external/~_repo_rules~example/file", "_repo_rules"))
    asserts.false(env, repository_rule_repo_in_path("external/example/file", "_repo_rules"))

    return unittest.end(env)

repository_paths_test = unittest.make(_repository_paths_test_impl)

def repository_paths_test_suite(name):
    repository_paths_test(name = name)
