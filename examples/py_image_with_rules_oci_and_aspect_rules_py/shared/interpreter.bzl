"""Shared interpreter layer for every py_image.

The layer is the registered aspect_rules_py toolchain, archived once in
//shared at the runfiles path the binary already uses.
"""

load("@aspect_bazel_lib//lib:tar.bzl", "mtree_mutate", "mtree_spec", "tar")

_TOOLCHAIN_FILES = "@python_3_12_x86_64_unknown_linux_gnu//:files"

def interpreter_runfiles_dir():
    """Return the interpreter directory inside the image.

    This is the canonical repository name of the registered toolchain, beneath
    /app.runfiles.

    Returns:
        The package_dir used when archiving the toolchain.
    """
    return "app.runfiles/" + Label(_TOOLCHAIN_FILES).repo_name

def interpreter_layer(name, visibility = None):
    """Build a gzip tar of the registered Python toolchain.

    Args:
        name: Name of the tar target consumed by py_image.
        visibility: Visibility of that tar. Intermediate targets stay private.
    """
    mtree_spec(
        name = "{}_mtree".format(name),
        srcs = [_TOOLCHAIN_FILES],
    )
    mtree_mutate(
        name = "{}_paths".format(name),
        mtree = ":{}_mtree".format(name),
        package_dir = interpreter_runfiles_dir(),
    )
    tar(
        name = name,
        srcs = [_TOOLCHAIN_FILES],
        compress = "gzip",
        mtree = ":{}_paths".format(name),
        visibility = visibility,
    )
