"""Utility helper functions for pip packages."""

load(
    "@oci_image_inference_config//:config.bzl",
    "PIP_HUB_REPO_NAME",
    "PIP_PACKAGE_SIZE_HINTS",
    "PIP_PACKAGE_SIZE_OVERRIDES",
    "PIP_WHEEL_SIZE_HINTS",
)

def configured_pip_package(label):
    """Return the package for a label in the configured pip hub, or None."""
    if PIP_HUB_REPO_NAME == None or label.repo_name != PIP_HUB_REPO_NAME:
        return None
    return label.package

def pip_inference_key(package):
    """Return the opaque inference identity for a pip distribution."""
    return "pip:{}".format(package)

def pip_package_size_hint(package):
    """Return the precomputed size hint for a package name.

    Args:
      package: Normalized pip distribution name.

    Returns:
      The precomputed size hint in bytes, or 0 if not found.
    """
    return PIP_PACKAGE_SIZE_HINTS.get(package, 0)

def pip_wheel_size_hint(package, wheel_filename):
    """Returns the selected wheel size, using an explicit package override if needed.

    Args:
        package: Normalized Python distribution name.
        wheel_filename: Selected wheel basename, or None for a source-built wheel.

    Returns:
        The positive compressed wheel size hint.
    """
    size = PIP_WHEEL_SIZE_HINTS.get(wheel_filename)
    if size != None:
        return size
    size = PIP_PACKAGE_SIZE_OVERRIDES.get(package)
    if size != None:
        return size
    fail("no pip size hint configured for package {} and wheel {}".format(package, wheel_filename or "<source-built>"))

def sorted_by_size_hint(size_hint_dict = PIP_PACKAGE_SIZE_HINTS):
    """Return a list with all pip packages sorted by size hint."""

    return [
        pkg
        for size_hint, pkg in sorted([
            (size_hint, pkg)
            for pkg, size_hint in size_hint_dict.items()
        ])
    ]
