"""
Utility functions for apt packages.
"""

load("@oci_image_inference_config//:config.bzl", "APT_PACKAGE_SIZE_HINTS")

def apt_package_size_hint(package_label):
    """Return the configured size hint for an exact apt package label.

    Args:
        package_label: Exact Label of the rules_distroless package target.

    Returns:
        The configured size hint in bytes.
    """
    key = str(package_label)
    size = APT_PACKAGE_SIZE_HINTS.get(key)
    if size == None:
        fail("no APT package size hint configured for {}".format(key))
    return size
