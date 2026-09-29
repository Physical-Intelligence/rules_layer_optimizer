"""Tests for pip_layer_aspect."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//python/private:aspect_rules_py.bzl", "wheel_identity", "wheel_package")
load("//python/private:pip_deps.bzl", "PipDepsInfo", "merge_pip_deps")
load("//python/private:pip_layer_aspect.bzl", "PipLayerArtifactsInfo", "merge_pip_package_tars")

def _whl_install_package_test_impl(ctx):
    env = unittest.begin(ctx)

    label = "@@aspect_rules_py++uv+whl_install__some_project__numpy__2_0_0//:install"

    asserts.equals(
        env,
        "numpy",
        wheel_package(label),
    )
    asserts.equals(env, label.split("//", 1)[0], wheel_identity(label))
    asserts.equals(
        env,
        "numpy",
        wheel_package("@@aspect_rules_py~~uv~whl_install__other_project__numpy__2_0_0//:install"),
    )
    asserts.equals(env, None, wheel_package("//python:defs.bzl"))

    return unittest.end(env)

whl_install_package_test = unittest.make(_whl_install_package_test_impl)

def _collect_impl(ctx):
    """Plain consumer that just exposes whatever the aspect produced."""
    package_tars = {}
    pip_deps = {}
    pip_sources = {}
    for dep in ctx.attr.deps:
        if PipLayerArtifactsInfo in dep:
            merge_pip_package_tars(package_tars, dep[PipLayerArtifactsInfo].package_tars, ctx.label)
        if PipDepsInfo in dep:
            merge_pip_deps(pip_deps, pip_sources, dep[PipDepsInfo], ctx.label)
    return [
        DefaultInfo(files = depset([info.tar for info in package_tars.values()])),
        PipLayerArtifactsInfo(package_tars = package_tars),
        PipDepsInfo(pip_deps = pip_deps, pip_sources = pip_sources, sorted_pip_deps = sorted(pip_deps.keys())),
    ]

def _pip_provider_stub_impl(ctx):
    tar = ctx.actions.declare_file(ctx.label.name + ".tar.zst")
    ctx.actions.write(tar, "")
    package = ctx.attr.package
    source = ctx.attr.source
    return [
        PipLayerArtifactsInfo(package_tars = {
            package: struct(group = None, size_bytes = 1, source = source, tar = tar),
        }),
        PipDepsInfo(
            pip_deps = {package: 1},
            pip_sources = {package: source},
            sorted_pip_deps = [package],
        ),
    ]

_pip_provider_stub = rule(
    implementation = _pip_provider_stub_impl,
    attrs = {
        "package": attr.string(mandatory = True),
        "source": attr.string(mandatory = True),
    },
)

_merge_stub_outputs = rule(
    implementation = _collect_impl,
    attrs = {"deps": attr.label_list()},
)

def _merge_current_wheel_impl(ctx):
    pip_deps = {}
    pip_sources = {}
    for dep in ctx.attr.deps:
        merge_pip_deps(pip_deps, pip_sources, dep[PipDepsInfo], ctx.label)
    package = ctx.attr.package
    merge_pip_deps(
        pip_deps,
        pip_sources,
        PipDepsInfo(
            pip_deps = {package: 1},
            pip_sources = {package: ctx.attr.source},
            sorted_pip_deps = [package],
        ),
        ctx.label,
    )
    return [PipDepsInfo(
        pip_deps = pip_deps,
        pip_sources = pip_sources,
        sorted_pip_deps = sorted(pip_deps.keys()),
    )]

_merge_current_wheel = rule(
    implementation = _merge_current_wheel_impl,
    attrs = {
        "deps": attr.label_list(providers = [PipDepsInfo]),
        "package": attr.string(mandatory = True),
        "source": attr.string(mandatory = True),
    },
)

def _expect_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.message)
    return analysistest.end(env)

_expect_failure_test = analysistest.make(
    _expect_failure_test_impl,
    attrs = {"message": attr.string(mandatory = True)},
    expect_failure = True,
)

def pip_layer_aspect_test_suite(name):
    """Suite asserting pip_layer_aspect declares per-package tars and PipDepsInfo.

    Args:
        name: prefix for the generated test rules.
    """

    whl_install_package_test(
        name = name + "_package_name_test",
    )

    _pip_provider_stub(
        name = name + "_collision_a",
        package = "example",
        source = "@@project_a//:wheel",
        tags = ["manual"],
    )
    _pip_provider_stub(
        name = name + "_collision_b",
        package = "example",
        source = "@@project_b//:wheel",
        tags = ["manual"],
    )
    _merge_stub_outputs(
        name = name + "_collision_subject",
        deps = [
            ":" + name + "_collision_a",
            ":" + name + "_collision_b",
        ],
        tags = ["manual"],
    )
    _expect_failure_test(
        name = name + "_collision_test",
        target_under_test = ":" + name + "_collision_subject",
        message = "reaches multiple wheels for pip distribution 'example'",
    )
    _merge_current_wheel(
        name = name + "_parent_child_collision_subject",
        deps = [":" + name + "_collision_a"],
        package = "example",
        source = "@@parent_project//:wheel",
        tags = ["manual"],
    )
    _expect_failure_test(
        name = name + "_parent_child_collision_test",
        target_under_test = ":" + name + "_parent_child_collision_subject",
        message = "reaches multiple wheels for pip distribution 'example'",
    )

    native.test_suite(
        name = name,
        tests = [
            ":" + name + "_package_name_test",
            ":" + name + "_collision_test",
            ":" + name + "_parent_child_collision_test",
        ],
    )
