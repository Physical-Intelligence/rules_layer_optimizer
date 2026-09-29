"""Module extension configuration for OCI image inference rules."""

# buildifier: disable=bzl-visibility
load("//apt/private:apt_size_hints.bzl", "parse_apt_lock_size_hints", "render_apt_size_hints_bzl")

# buildifier: disable=bzl-visibility
load("//python/private:pip_size_hints_repository.bzl", "parse_pip_size_overrides", "parse_uv_lock_size_hints", "render_pip_size_hint_bzl")

def _inference_config_repository_impl(rctx):
    rctx.file("BUILD.bazel", "exports_files([\"config.bzl\"])\n")
    pip_hub_repo_name = rctx.attr.pip_hub.repo_name if rctx.attr.pip_hub else None
    apt_package_size_hints = {}
    for index in range(len(rctx.attr.apt_locks)):
        lock_hints = parse_apt_lock_size_hints(
            rctx.read(rctx.attr.apt_locks[index]),
            rctx.attr.apt_dependency_sets[index],
            rctx.attr.apt_repositories[index].repo_name,
        )
        for package, size in lock_hints.items():
            previous_size = apt_package_size_hints.get(package)
            apt_package_size_hints[package] = max(previous_size or 0, size)

    pip_size_hints = parse_uv_lock_size_hints(
        rctx.read(rctx.attr.pip_lock),
        rctx.attr.pip_size_overrides,
    ) if rctx.attr.pip_lock else parse_pip_size_overrides(rctx.attr.pip_size_overrides)

    rctx.file(
        "config.bzl",
        "\n".join([
            '"""Generated OCI image inference configuration. Do not edit."""',
            "",
            "DEPENDENCY_ATTRIBUTES = {}".format(repr(rctx.attr.dependency_attributes)),
            "PIP_HUB_REPO_NAME = {}".format(repr(pip_hub_repo_name)),
            "",
        ]) + render_apt_size_hints_bzl(apt_package_size_hints) + "\n" + render_pip_size_hint_bzl(pip_size_hints),
    )

_inference_config_repository = repository_rule(
    implementation = _inference_config_repository_impl,
    attrs = {
        "apt_dependency_sets": attr.string_list(),
        "apt_locks": attr.label_list(allow_files = [".json"]),
        "apt_repositories": attr.label_list(),
        "dependency_attributes": attr.string_list(),
        "pip_hub": attr.label(),
        "pip_lock": attr.label(allow_single_file = [".lock"]),
        "pip_size_overrides": attr.string_dict(),
    },
)

def _oci_image_inference_impl(module_ctx):
    non_root_configurations = [
        configuration
        for module in module_ctx.modules
        if not module.is_root
        for configuration in module.tags.configure
    ]
    if non_root_configurations:
        fail("Only the root module may configure OCI image inference")

    configurations = [
        configuration
        for module in module_ctx.modules
        if module.is_root
        for configuration in module.tags.configure
    ]
    if len(configurations) > 1:
        fail("The root module may declare at most one oci_image_inference.configure tag")
    configuration = configurations[0] if configurations else struct(
        dependency_attributes = ["deps", "src", "srcs", "data", "actual", "venv"],
        pip_hub = None,
    )

    non_root_apt_size_hints = [
        apt_size_hint
        for module in module_ctx.modules
        if not module.is_root
        for apt_size_hint in module.tags.apt_size_hint
    ]
    if non_root_apt_size_hints:
        fail("Only the root module may configure APT size hints")

    non_root_pip_size_hints = [
        pip_size_hint
        for module in module_ctx.modules
        if not module.is_root
        for pip_size_hint in module.tags.pip_size_hint
    ]
    if non_root_pip_size_hints:
        fail("Only the root module may configure pip size hints")

    apt_size_hints = [
        apt_size_hint
        for module in module_ctx.modules
        if module.is_root
        for apt_size_hint in module.tags.apt_size_hint
    ]
    pip_size_hints = [
        pip_size_hint
        for module in module_ctx.modules
        if module.is_root
        for pip_size_hint in module.tags.pip_size_hint
    ]
    if len(pip_size_hints) > 1:
        fail("Declare at most one oci_image_inference.pip_size_hint tag")

    if pip_size_hints and not pip_size_hints[0].lock and not pip_size_hints[0].size_overrides:
        fail("pip_size_hint requires a lock or explicit size_overrides")

    _inference_config_repository(
        name = "oci_image_inference_config",
        apt_dependency_sets = [hint.dependency_set for hint in apt_size_hints],
        apt_locks = [hint.lock for hint in apt_size_hints],
        apt_repositories = [hint.repository for hint in apt_size_hints],
        dependency_attributes = configuration.dependency_attributes,
        pip_hub = configuration.pip_hub,
        pip_lock = pip_size_hints[0].lock if pip_size_hints else None,
        pip_size_overrides = pip_size_hints[0].size_overrides if pip_size_hints else {},
    )
    return module_ctx.extension_metadata(reproducible = True)

oci_image_inference = module_extension(
    implementation = _oci_image_inference_impl,
    tag_classes = {
        "apt_size_hint": tag_class(attrs = {
            "dependency_set": attr.string(mandatory = True),
            "lock": attr.label(allow_single_file = [".json"], mandatory = True),
            "repository": attr.label(mandatory = True),
        }),
        "configure": tag_class(attrs = {
            "dependency_attributes": attr.string_list(default = ["deps", "src", "srcs", "data", "actual", "venv"]),
            "pip_hub": attr.label(),
        }),
        "pip_size_hint": tag_class(attrs = {
            "lock": attr.label(allow_single_file = [".lock"]),
            "size_overrides": attr.string_dict(),
        }),
    },
)
