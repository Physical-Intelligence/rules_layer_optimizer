"""Shared dependency-graph matching for OCI image inference rules."""

load("@oci_image_inference_config//:config.bzl", "DEPENDENCY_ATTRIBUTES")

DependencyGraphInfo = provider(
    "Labels visited while walking a target graph for image inference.",
    fields = {
        "labels": "Transitive depset of exact Bazel Label values for visited targets.",
    },
)

DependencyKeyInfo = provider(
    "Opaque dependency identities supplied by inference adapters.",
    fields = {
        "keys": "Dict-set of adapter-defined dependency identity strings.",
    },
)

def dependency_labels(targets):
    """Return exact label strings visited below aspect-applied targets.

    Args:
        targets: Targets decorated with dependency graph or identity providers.

    Returns:
        A dict-set of exact label strings.
    """
    labels = {}
    for target in targets:
        if DependencyGraphInfo in target:
            for label in target[DependencyGraphInfo].labels.to_list():
                labels[str(label)] = None
    return labels

def dependency_identities(targets):
    """Return exact labels and opaque adapter keys visited below targets.

    Args:
        targets: Targets decorated with dependency graph or identity providers.

    Returns:
        A dict-set of exact labels and adapter keys.
    """
    identities = dependency_labels(targets)
    for target in targets:
        if DependencyKeyInfo in target:
            identities.update(target[DependencyKeyInfo].keys)
    return identities

def inference_matches(for_deps, labels):
    """Return whether any inference trigger occurs in a collected label set."""
    return any([dep in labels for dep in for_deps])

def validate_inference_triggers(name, for_deps):
    """Declare an analysis test that resolves an inference's trigger labels."""
    _inference_triggers_test(
        name = name,
        deps = for_deps,
        visibility = ["//visibility:private"],
    )

def _dependency_graph_aspect_impl(target, ctx):
    transitive_labels = []
    for attr_name in DEPENDENCY_ATTRIBUTES:
        attr_value = getattr(ctx.rule.attr, attr_name, None)
        if type(attr_value) == "list":
            transitive_labels.extend([
                dep[DependencyGraphInfo].labels
                for dep in attr_value
                if DependencyGraphInfo in dep
            ])
        elif attr_value and DependencyGraphInfo in attr_value:
            transitive_labels.append(attr_value[DependencyGraphInfo].labels)

    return [DependencyGraphInfo(labels = depset(
        direct = [target.label],
        transitive = transitive_labels,
    ))]

dependency_graph_aspect = aspect(
    implementation = _dependency_graph_aspect_impl,
    attr_aspects = DEPENDENCY_ATTRIBUTES,
)

def _inference_triggers_test_impl(_ctx):
    return [AnalysisTestResultInfo(success = True, message = "")]

_inference_triggers_test = rule(
    implementation = _inference_triggers_test_impl,
    test = True,
    analysis_test = True,
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            doc = "Inference trigger labels to validate during test analysis.",
        ),
    },
)
