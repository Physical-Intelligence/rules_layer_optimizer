"""Interpreter path inside images built by the py_image macro.

rules_python's py_image_layer archives the binary's interpreter at its
runfiles path. This helper names that directory for the image test.
"""

_TOOLCHAIN_FILES = "@python_3_12_x86_64-unknown-linux-gnu//:files"

def interpreter_runfiles_dir():
    """Return the interpreter directory inside the image.

    This is the canonical repository name of the registered toolchain, beneath
    /app.runfiles.

    Returns:
        The runfiles directory of the rules_python toolchain.
    """
    return "app.runfiles/" + Label(_TOOLCHAIN_FILES).repo_name
