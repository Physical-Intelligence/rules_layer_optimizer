"""Providers shared by OCI layer grouping rules."""

LayerTarsInfo = provider(
    "Explicit OCI layer tar files emitted by a target.",
    fields = {
        "tars": "Ordered list of tar Files eligible for layer optimization.",
    },
)

SizeHintInfo = provider(
    "Optional compressed-size metadata for OCI layer tar files.",
    fields = {
        "sizes": "Dict from a LayerTarsInfo File to a positive size hint in bytes.",
    },
)

def layer_group(name, targets, overflow = "individual"):
    """Defines an ordered logical group of layer tar targets.

    Args:
        name: Stable group name used for generated targets and output groups.
        targets: Ordered list of tar-producing targets.
        overflow: How low-value or overflow files are handled. Use "flatten"
            to fold them into one flat layer, or "individual" to keep every
            file as a fixed individual layer.

    Returns:
        A struct consumed by `optimized_layers(groups = [...])`.
    """
    if overflow not in ["flatten", "individual"]:
        fail("layer_group overflow for '{}' must be 'flatten' or 'individual', got '{}'".format(name, overflow))
    return struct(
        name = name,
        targets = targets,
        overflow = overflow,
    )

def merge_size_hints(size_hints, additions, owner):
    """Merge file size hints, rejecting conflicting metadata.

    Args:
        size_hints: Existing File-to-size dict.
        additions: File-to-size dict to merge.
        owner: Description of the target or composition being validated.

    Returns:
        A new dict containing both sets of hints.
    """
    merged = dict(size_hints)
    for file, size in additions.items():
        previous_size = merged.get(file)
        if previous_size != None and previous_size != size:
            fail("{} provides conflicting size hints {} and {} for {}".format(
                owner,
                previous_size,
                size,
                file.short_path,
            ))
        merged[file] = size
    return merged
