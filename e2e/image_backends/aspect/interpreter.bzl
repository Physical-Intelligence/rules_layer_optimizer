"""Interpreter layout for the aspect_rules_py image."""

def interpreter_path():
    """Return the configured interpreter's destination in the image."""
    return "app.runfiles/" + Label("@python_3_12_x86_64_unknown_linux_gnu//:files").repo_name
