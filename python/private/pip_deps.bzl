"""
Aspect to collect pip package dependencies.
"""

load("@oci_image_inference_config//:config.bzl", "DEPENDENCY_ATTRIBUTES")

# buildifier: disable=bzl-visibility
load("//inference/private:dependency_inference.bzl", "DependencyKeyInfo")
load("//python/private:aspect_rules_py.bzl", "wheel_identity", "wheel_package")
load("//python/private:pip_utils.bzl", "pip_inference_key", "pip_package_size_hint")
load("//python/private:rules_python_wheel.bzl", rules_python_package = "wheel_package")

PipDepsInfo = provider(
    "Pip deps info",
    fields = {
        "pip_deps": "Dict mapping normalized distribution names to size hints.",
        "pip_sources": "Dict mapping normalized distribution names to canonical wheel repository identities.",
    },
)

def merge_pip_deps(pip_deps, pip_sources, additions, owner):
    """Merge PipDepsInfo, rejecting one distribution from multiple wheels.

    Args:
        pip_deps: Mutable package-to-size mapping.
        pip_sources: Mutable package-to-wheel-identity mapping.
        additions: Dependency provider containing additional package metadata.
        owner: Target identity used in conflict diagnostics.
    """
    for package, size in additions.pip_deps.items():
        source = additions.pip_sources.get(package)
        previous_source = pip_sources.get(package)
        if previous_source != None and source != None and previous_source != source:
            fail("{} reaches multiple wheels for pip distribution '{}': {} and {}".format(
                owner,
                package,
                previous_source,
                source,
            ))
        previous_size = pip_deps.get(package)
        if previous_size != None and previous_size != size:
            fail("{} provides conflicting size hints {} and {} for pip distribution '{}'".format(
                owner,
                previous_size,
                size,
                package,
            ))
        pip_deps[package] = size
        if source != None:
            pip_sources[package] = source

def _pip_deps_aspect_impl(target, ctx):
    """
    Traverse the dependencies of a py_binary and collect pip package dependencies.

    Args:
        target: The target to traverse.
        ctx: The aspect context.

    Returns:
        A list of providers.
    """
    pip_deps = {}
    pip_sources = {}

    if ctx.rule.kind in ["py_library", "py_binary", "whl_install", "alias"]:
        package = wheel_package(target.label) or rules_python_package(ctx)
        if package != None:
            pip_deps[package] = pip_package_size_hint(package)
            pip_sources[package] = wheel_identity(target.label) or "@@" + target.label.repo_name

    # Propagate pip deps from our dependencies.
    for attr_name in DEPENDENCY_ATTRIBUTES:
        attr_value = getattr(ctx.rule.attr, attr_name, None)
        if attr_value:
            if type(attr_value) == "list":
                for dep in attr_value:
                    if PipDepsInfo in dep:
                        merge_pip_deps(pip_deps, pip_sources, dep[PipDepsInfo], target.label)
            elif PipDepsInfo in attr_value:
                merge_pip_deps(pip_deps, pip_sources, attr_value[PipDepsInfo], target.label)

    return [
        DefaultInfo(files = depset()),
        DependencyKeyInfo(keys = {
            pip_inference_key(package): None
            for package in pip_deps.keys()
        }),
        PipDepsInfo(
            pip_deps = pip_deps,
            pip_sources = pip_sources,
        ),
    ]

pip_deps_aspect = aspect(
    implementation = _pip_deps_aspect_impl,
    attr_aspects = DEPENDENCY_ATTRIBUTES,
    provides = [DefaultInfo, DependencyKeyInfo, PipDepsInfo],
)
