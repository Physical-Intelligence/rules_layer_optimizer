"""Small distroless-shaped package repository for adapter contract tests."""

def _apt_fixture_impl(rctx):
    rctx.file("BUILD.bazel", 'exports_files(["anchor"])')
    rctx.file("anchor", "")
    rctx.file("bash/payload", "fixture package\n")
    rctx.file("bash/BUILD.bazel", '''
load("@aspect_bazel_lib//lib:tar.bzl", "tar")
package(default_visibility = ["//visibility:public"])
tar(name = "data", srcs = ["payload"], compress = "gzip")
filegroup(name = "bash", srcs = [":data"])
''')

apt_fixture = repository_rule(implementation = _apt_fixture_impl)
