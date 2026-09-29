"""Infer apt packages for OCI images from a binary's dependency graph.

Callers register their own mappings with `apt_inference` rather than relying on
a global policy dict. Each image calls `inferred_apt_deps`, which depends on
those inference targets, walks the binary with an aspect, and includes only the
mappings that matched.
"""

load("//apt/private:distroless.bzl", "apt_size_hint_aspect")

# buildifier: disable=bzl-visibility
load("//inference/private:dependency_inference.bzl", "dependency_graph_aspect", "dependency_identities", "inference_matches", "validate_inference_triggers")

# buildifier: disable=bzl-visibility
load("//inference/private:inferred_layers.bzl", "LayerInferenceBundleInfo", "LayerInferenceInfo")

# buildifier: disable=bzl-visibility
load("//layers/private:layer_groups.bzl", "LayerTarsInfo", "SizeHintInfo", "merge_size_hints")

def _apt_inference_rule_impl(ctx):
    files = [p.files for p in ctx.attr.packages + ctx.attr.tars]
    sizes = {}
    for package in ctx.attr.packages:
        if SizeHintInfo in package:
            sizes = merge_size_hints(sizes, package[SizeHintInfo].sizes, ctx.label)
    return [
        DefaultInfo(files = depset(transitive = files)),
        LayerInferenceInfo(for_deps = ctx.attr.for_deps, for_keys = ctx.attr.for_keys),
        SizeHintInfo(sizes = sizes),
    ]

_apt_inference_rule = rule(
    implementation = _apt_inference_rule_impl,
    doc = """Adapt APT package tars and logical dependency keys into a layer inference.

`packages` is the place for a caller-owned platform `select()`. Those apt
tars stay off the Python dependency graph, so host tests do not fetch debs.
""",
    attrs = {
        "for_deps": attr.string_list(mandatory = True),
        "for_keys": attr.string_list(mandatory = True),
        "packages": attr.label_list(
            default = [],
            aspects = [apt_size_hint_aspect],
            doc = "Distroless apt package targets, optionally selected by platform.",
        ),
        "tars": attr.label_list(
            default = [],
            doc = "Non-apt tars such as compatibility shims.",
        ),
    },
)

def apt_inference(
        name,
        packages = [],
        tars = [],
        for_deps = [],
        for_keys = [],
        **kwargs):
    """Register one apt inference and a test that validates its trigger labels.

    The inference rule stores dependency identities as strings so its dependency
    graph only contains apt packages. The generated test resolves the configured
    dependency labels through a label_list without adding them to image analysis.

    Args:
        name: Name of the apt inference target.
        for_deps: Bazel labels that trigger this inference. Use python:inference.bzl for logical pip-package matching.
        for_keys: Additional opaque keys supplied by a dependency adapter.
        packages: Distroless apt package targets, optionally selected by platform.
        tars: Non-apt tars such as compatibility shims.
        **kwargs: Additional attributes for the apt inference target.
    """
    triggers = _inference_triggers(for_deps)
    _apt_inference_rule(
        name = name,
        for_deps = triggers.labels,
        for_keys = for_keys,
        packages = packages,
        tars = tars,
        **kwargs
    )
    validate_inference_triggers(
        name = name + "_for_deps_test",
        for_deps = for_deps,
    )

def inferred_apt_deps_rule_impl(ctx):
    """Return apt package tars inferred from the given deps.

    Exposes selected apt package tars and forwards primary-file size hints from
    `apt_size_hint_aspect`. Transitive package files remain in DefaultInfo
    without size hints, allowing `optimize_layers` to fold them into the apt
    flat layer without this rule knowing about layer policy.

    Args:
        ctx: Rule context with inferred layers, extra packages, and base packages.

    Returns:
        DefaultInfo of all selected apt tars, LayerTarsInfo of unique files,
        and SizeHintInfo of primary-file sizes.
    """
    all_pkg_depsets = []
    all_pkg_files = []
    all_pkg_files_seen = {}
    file_sizes = {}

    for package in ctx.attr.base_packages:
        all_pkg_depsets.append(package.files)
        for f in package.files.to_list():
            if f not in all_pkg_files_seen:
                all_pkg_files_seen[f] = True
                all_pkg_files.append(f)
        if SizeHintInfo in package:
            file_sizes = merge_size_hints(file_sizes, package[SizeHintInfo].sizes, ctx.label)

    seen = _seen_labels(ctx)
    for entry in _inference_entries(ctx):
        if not inference_matches(entry.for_deps + entry.for_keys, seen):
            continue
        all_pkg_depsets.append(entry.files)
        for f in entry.files.to_list():
            if f not in all_pkg_files_seen:
                all_pkg_files_seen[f] = True
                all_pkg_files.append(f)
        file_sizes = merge_size_hints(file_sizes, entry.sizes, ctx.label)

    for package in ctx.attr.packages:
        all_pkg_depsets.append(package.files)
        for f in package.files.to_list():
            if f not in all_pkg_files_seen:
                all_pkg_files_seen[f] = True
                all_pkg_files.append(f)
        if SizeHintInfo in package:
            file_sizes = merge_size_hints(file_sizes, package[SizeHintInfo].sizes, ctx.label)

    return [
        DefaultInfo(
            files = depset(transitive = all_pkg_depsets),
        ),
        LayerTarsInfo(tars = all_pkg_files),
        SizeHintInfo(sizes = file_sizes),
    ]

def make_inferred_apt_deps(dependency_aspects = []):
    """Create an inference rule with additional dependency-identity aspects."""
    return rule(
        implementation = inferred_apt_deps_rule_impl,
        attrs = {
            "deps": attr.label_list(aspects = [dependency_graph_aspect] + dependency_aspects),
            "inferences": attr.label_list(default = []),
            "base_packages": attr.label_list(default = [], aspects = [apt_size_hint_aspect]),
            "packages": attr.label_list(default = [], aspects = [apt_size_hint_aspect]),
        },
    )

inferred_apt_deps_rule = make_inferred_apt_deps()

def _seen_labels(ctx):
    return dependency_identities(ctx.attr.deps)

def _inference_triggers(for_deps):
    return struct(labels = [str(native.package_relative_label(dep)) for dep in for_deps], keys = [])

def _inference_entries(ctx):
    entries = []
    for inference in ctx.attr.inferences:
        if LayerInferenceBundleInfo in inference:
            entries.extend(inference[LayerInferenceBundleInfo].entries)
        elif LayerInferenceInfo in inference:
            sizes = inference[SizeHintInfo].sizes if SizeHintInfo in inference else {}
            entries.append(struct(
                for_deps = tuple(inference[LayerInferenceInfo].for_deps),
                for_keys = tuple(inference[LayerInferenceInfo].for_keys),
                files = inference.files,
                sizes = sizes,
            ))
        else:
            fail("{} is not a layer_inference or layer_inference_bundle target".format(inference.label))
    return entries
