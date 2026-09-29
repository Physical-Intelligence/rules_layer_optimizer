"""Shared collection and ordering of per-package layer artifacts."""

load("//layers:providers.bzl", "LayerTarsInfo", "SizeHintInfo")
load("//python/private:pip_deps.bzl", "PipDepsInfo", "merge_pip_deps")
load("//python/private:pip_layer_artifacts.bzl", "PipLayerArtifactsInfo", "merge_pip_package_tars")

def make_pip_layer_reducer(package_aspect):
    """Create a package collector for a Python dependency adapter."""
    return rule(
        doc = "Collects per-package pip tars (from `pip_layer_aspect`) and exposes size hints.",
        implementation = _pip_layer_reducer_impl,
        attrs = {
            "deps": attr.label_list(aspects = [package_aspect]),
        },
        provides = [DefaultInfo, LayerTarsInfo, SizeHintInfo, PipLayerArtifactsInfo, PipDepsInfo],
    )

def _pip_layer_reducer_impl(ctx):
    """Reduces `PipLayerArtifactsInfo` from `pip_layer_aspect` into size hints.

    The aspect emits one tar per pip package at that package's own
    namespace (action-deduped across binaries); this rule walks the
    transitive provider and exposes every package tar with its generated size
    hint. The optimizer owns the threshold decision so it can raise the
    effective cutoff when the final image-wide layer budget would be exceeded.

    Candidate tars are sorted largest-first so they appear first in the
    consuming image when retained as individual layers. That also makes the
    smallest candidates the first ones folded into the flat pip layer when
    either the static threshold or dynamic layer budget requires it.
    """
    package_tars = {}
    pip_deps = {}
    pip_sources = {}
    for dep in ctx.attr.deps:
        if PipLayerArtifactsInfo in dep:
            merge_pip_package_tars(package_tars, dep[PipLayerArtifactsInfo].package_tars, ctx.label)
        if PipDepsInfo in dep:
            merge_pip_deps(pip_deps, pip_sources, dep[PipDepsInfo], ctx.label)

    candidate_entries = []
    file_sizes = {}
    for normalized_label, info in sorted(package_tars.items()):
        candidate_entries.append((info.size_bytes, normalized_label, info.tar))
        file_sizes[info.tar] = info.size_bytes

    candidate_entries = sorted(candidate_entries, key = lambda x: (-x[0], x[1]))
    candidate_files = [tar_file for _, _, tar_file in candidate_entries]

    return [
        DefaultInfo(files = depset(candidate_files)),
        LayerTarsInfo(tars = candidate_files),
        SizeHintInfo(sizes = file_sizes),
        PipLayerArtifactsInfo(package_tars = package_tars),
        PipDepsInfo(
            pip_deps = pip_deps,
            pip_sources = pip_sources,
        ),
    ]
