"""Adapter for rules_python's tagged pip py_library targets."""

def wheel_package(ctx):
    """Read distribution metadata without parsing generated repository names.

    Args:
        ctx: Aspect context at a pip py_library.

    Returns:
        Normalized distribution name, or None for other targets.
    """
    if ctx.rule.kind != "py_library":
        return None
    for tag in getattr(ctx.rule.attr, "tags", []):
        if tag.startswith("pypi_name="):
            return normalize_package(tag.removeprefix("pypi_name="))
    return None

def normalize_package(name):
    """Normalize a Python distribution name to its pip hub spelling.

    Args:
        name: Distribution name from wheel metadata.

    Returns:
        Lowercase distribution name with collapsed underscore separators.
    """
    result = []
    for char in name.lower().elems():
        if char in "-_.":
            if not result or result[-1] != "_":
                result.append("_")
        else:
            result.append(char)
    return "".join(result)

def wheel_files(target):
    """Return this wheel's runtime files, excluding transitive distributions."""
    return [
        file
        for file in target[DefaultInfo].default_runfiles.files.to_list()
        if file.owner.repo_name == target.label.repo_name
    ]
