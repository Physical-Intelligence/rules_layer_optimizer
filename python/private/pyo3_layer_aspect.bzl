"""Collect PyO3 extension artifacts from a Python target's dependency graph."""

Pyo3ArtifactsInfo = provider(
    doc = "PyO3 extension artifacts keyed by their owning target label.",
    fields = {
        "artifacts": "Dict mapping target labels to their extension shared-object Files.",
    },
)

_TRAVERSED_ATTRS = ["deps", "data", "src", "actual", "venv"]

def _pyo3_layer_aspect_impl(target, ctx):
    artifacts = {}
    for attr_name in _TRAVERSED_ATTRS:
        attr = getattr(ctx.rule.attr, attr_name, None)
        if attr == None:
            continue
        deps = attr if type(attr) == "list" else [attr]
        for dep in deps:
            if Pyo3ArtifactsInfo in dep:
                artifacts.update(dep[Pyo3ArtifactsInfo].artifacts)

    if ctx.rule.kind == "py_pyo3_library":
        extension_files = [
            file
            for file in target[DefaultInfo].files.to_list()
            if file.basename.endswith(".so")
        ]
        if extension_files:
            artifacts[str(target.label)] = extension_files

    return [Pyo3ArtifactsInfo(artifacts = artifacts)]

pyo3_layer_aspect = aspect(
    implementation = _pyo3_layer_aspect_impl,
    attr_aspects = _TRAVERSED_ATTRS,
    provides = [Pyo3ArtifactsInfo],
)
