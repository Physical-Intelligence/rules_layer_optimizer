"""Infer OCI image layer tars from a target's dependency graph."""

load("//inference/private:dependency_inference.bzl", "dependency_graph_aspect", "dependency_identities", "inference_matches", "validate_inference_triggers")

# buildifier: disable=bzl-visibility
load("//layers/private:layer_groups.bzl", "LayerTarsInfo", "SizeHintInfo", "merge_size_hints")

LayerInferenceInfo = provider(
    "One mapping from dependency identities to OCI layer tars.",
    fields = {
        "for_deps": "Exact Bazel label strings that trigger this mapping.",
        "for_keys": "Opaque adapter-defined keys that trigger this mapping.",
    },
)

LayerInferenceBundleInfo = provider(
    "Flattened layer_inference entries.",
    fields = {
        "entries": "List of structs with for_deps, files, and sizes.",
    },
)

def layer_inference(name, for_deps, layers, for_keys = [], **kwargs):
    """Register layer-producing targets to include when dependencies occur.

    Targets may provide `LayerTarsInfo` to select their OCI layer outputs and
    `SizeHintInfo` to participate in size-aware layer optimization.
    """
    triggers = _inference_triggers(for_deps)
    _layer_inference(
        name = name,
        for_deps = triggers.labels,
        for_keys = for_keys,
        layers = layers,
        **kwargs
    )
    validate_inference_triggers(
        name = name + "_for_deps_test",
        for_deps = for_deps,
    )

def _layer_inference_impl(ctx):
    files = []
    sizes = {}
    for layer in ctx.attr.layers:
        layer_files = _layer_files(layer)
        files.append(depset(layer_files))
        if SizeHintInfo in layer:
            layer_sizes = layer[SizeHintInfo].sizes
            selected = {file: None for file in layer_files}
            for file in layer_sizes:
                if file not in selected:
                    fail("{} provides a size hint for non-layer output {}".format(layer.label, file.short_path))
            sizes = merge_size_hints(sizes, layer_sizes, ctx.label)
    return [
        DefaultInfo(files = depset(transitive = files)),
        LayerInferenceInfo(for_deps = ctx.attr.for_deps, for_keys = ctx.attr.for_keys),
        SizeHintInfo(sizes = sizes),
    ]

_layer_inference = rule(
    implementation = _layer_inference_impl,
    attrs = {
        "for_deps": attr.string_list(mandatory = True),
        "for_keys": attr.string_list(mandatory = True),
        "layers": attr.label_list(mandatory = True),
    },
)

def _layer_inference_bundle_impl(ctx):
    return [LayerInferenceBundleInfo(entries = [
        struct(
            files = inference.files,
            for_deps = tuple(inference[LayerInferenceInfo].for_deps),
            for_keys = tuple(inference[LayerInferenceInfo].for_keys),
            sizes = inference[SizeHintInfo].sizes,
        )
        for inference in ctx.attr.inferences
    ])]

layer_inference_bundle = rule(
    implementation = _layer_inference_bundle_impl,
    attrs = {
        "inferences": attr.label_list(
            mandatory = True,
            providers = [[LayerInferenceInfo, SizeHintInfo]],
        ),
    },
)

def _inferred_layers_impl(ctx):
    files = []
    transitive_files = []
    sizes = {}
    seen_files = {}
    identities = dependency_identities(ctx.attr.deps)

    for entry in _inference_entries(ctx.attr.inferences):
        if not inference_matches(entry.for_deps + entry.for_keys, identities):
            continue
        transitive_files.append(entry.files)
        sizes = merge_size_hints(sizes, entry.sizes, ctx.label)
        for file in entry.files.to_list():
            if file not in seen_files:
                seen_files[file] = None
                files.append(file)

    return [
        DefaultInfo(files = depset(transitive = transitive_files)),
        LayerTarsInfo(tars = files),
        SizeHintInfo(sizes = sizes),
    ]

def make_inferred_layers(dependency_aspects = []):
    """Create an inference rule with additional dependency-identity aspects."""
    return rule(
        implementation = _inferred_layers_impl,
        attrs = {
            "deps": attr.label_list(aspects = [dependency_graph_aspect] + dependency_aspects),
            "inferences": attr.label_list(
                mandatory = True,
                providers = [
                    [LayerInferenceInfo, SizeHintInfo],
                    [LayerInferenceBundleInfo],
                ],
            ),
        },
    )

inferred_layers = make_inferred_layers()

def _inference_triggers(for_deps):
    return struct(labels = [str(native.package_relative_label(dep)) for dep in for_deps], keys = [])

def _layer_files(layer):
    if LayerTarsInfo in layer:
        return layer[LayerTarsInfo].tars

    files = layer.files.to_list()
    if len(files) > 1:
        fail("{} has multiple default outputs; provide LayerTarsInfo to select OCI layer tars".format(layer.label))
    return files

def _inference_entries(inferences):
    entries = []
    for inference in inferences:
        if LayerInferenceBundleInfo in inference:
            entries.extend(inference[LayerInferenceBundleInfo].entries)
        elif LayerInferenceInfo in inference:
            entries.append(struct(
                files = inference.files,
                for_deps = tuple(inference[LayerInferenceInfo].for_deps),
                for_keys = tuple(inference[LayerInferenceInfo].for_keys),
                sizes = inference[SizeHintInfo].sizes,
            ))
        else:
            fail("{} is not a layer_inference or layer_inference_bundle target".format(inference.label))
    return entries
