"""Shared per-distribution layer artifacts and ambiguity checks."""

PipLayerArtifactsInfo = provider(
    doc = "Per-package pip tars produced by pip_layer_aspect.",
    fields = {
        "package_tars": "Dict mapping normalized distribution name -> struct(tar=File, size_bytes=int, group=str|None, source=str).",
    },
)

def merge_pip_package_tars(package_tars, additions, owner):
    """Merge package tars, rejecting ambiguous distribution identities."""
    for package, info in additions.items():
        validate_package_source(package_tars, package, info.source, owner)
        package_tars[package] = info

def validate_package_source(package_tars, package, source, owner):
    """Reject two wheel identities for the same normalized distribution."""
    previous = package_tars.get(package)
    if previous != None and previous.source != source:
        fail("{} reaches multiple wheels for pip distribution '{}': {} and {}".format(
            owner,
            package,
            previous.source,
            source,
        ))
