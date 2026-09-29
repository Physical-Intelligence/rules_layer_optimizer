"""Compatibility adapter for aspect_rules_py wheel targets."""

load("@aspect_rules_py//py/private:providers.bzl", "PyWheelsInfo")

_WHL_INSTALL_MARKER = "whl_install__"

def wheel_package(label):
    """Return the distribution name encoded by an aspect_rules_py wheel repo.

    Args:
        label: Wheel target label or its string representation.

    Returns:
        Normalized distribution name, or None for non-wheel labels.
    """
    repository = str(label).split("//", 1)[0]
    marker_index = repository.find(_WHL_INSTALL_MARKER)
    if marker_index < 0:
        return None
    parts = repository[marker_index + len(_WHL_INSTALL_MARKER):].split("__")
    return parts[1] if len(parts) >= 3 else None

def wheel_identity(label):
    """Return the canonical generated repository that owns a wheel target."""
    repository = str(label).split("//", 1)[0]
    return repository if _WHL_INSTALL_MARKER in repository else None

def wheel_record(target):
    """Return the single wheel record owned by an aspect_rules_py leaf target.

    Args:
        target: Configured wheel-producing target.

    Returns:
        The unique installed-wheel record, or None.
    """
    if PyWheelsInfo not in target:
        return None
    wheels = target[PyWheelsInfo].wheels.to_list()
    if len(wheels) != 1:
        fail("{} must own exactly one wheel, got {}".format(target.label, len(wheels)))
    return wheels[0]

def selected_wheel_filename(ctx):
    """Return the selected wheel filename from an aspect_rules_py wheel rule.

    Args:
        ctx: Wheel rule analysis context.

    Returns:
        The source wheel basename, or None for a source-built wheel.
    """
    source = getattr(ctx.rule.attr, "src", None)
    if source == None:
        return None
    files = source.files.to_list()
    if len(files) != 1 or files[0].is_directory:
        return None
    return files[0].basename

def wheel_runfiles_prefix(wheel):
    """Return the runfiles destination corresponding to a wheel install tree.

    Args:
        wheel: Installed wheel metadata record.

    Returns:
        The wheel repository prefix beneath /app.runfiles.
    """
    site_packages_marker = "/lib/"
    marker_index = wheel.site_packages_rfpath.find(site_packages_marker)
    if marker_index < 0:
        fail("wheel site-packages path has no /lib/ segment: {}".format(wheel.site_packages_rfpath))
    return "./app.runfiles/" + wheel.site_packages_rfpath[:marker_index]
