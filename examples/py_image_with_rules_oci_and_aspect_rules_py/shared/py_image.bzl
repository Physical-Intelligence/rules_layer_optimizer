"""Caller-owned py_image macro with a two-argument call site.

The ruleset does not export this macro. Repositories own the base apt packages,
budget, and apt and environment mappings in //shared.
"""

load("@rules_layer_optimizer//layers:defs.bzl", "MAX_DOCKER_LAYERS", "layer_group")
load("@rules_layer_optimizer//layers:distroless.bzl", "optimized_layers")
load("@rules_layer_optimizer//python:aspect_rules_py.bzl", "py_image_layer")
load("@rules_layer_optimizer//python:inference.bzl", "env_file", "inferred_apt_deps")
load("@rules_oci//oci:defs.bzl", "oci_image")

# Installed instead of an OCI base image. Enough for a py_binary to run.
_BASE_APT_PACKAGES = [
    "@noble//base-files",
    "@noble//ca-certificates",
    "@noble//netbase",
    "@noble//libssl3t64",
    "@noble//openssl",
    "@noble//libstdc++6",
    "@noble//tzdata",
    "@noble//bash",
    "@noble//coreutils",
    "@noble//gawk",
    "@noble//sed",
    "@noble//grep",
]

def py_image(name, binary):
    """Build an OCI image from an aspect_rules_py py_binary.

    Args:
        name: Image target name.
        binary: py_binary to package. Its main-repo path is `package/name`.
    """
    layers = "{}_layers".format(name)
    py_image_layer(
        name = layers,
        binary = binary,
        compress = "gzip",
        interpreter_tar = "//shared:python_interpreter",
        python_toolchain = "@python_interpreters//:current_py_toolchain",
        strip_prefix = _binary_path(binary),
    )

    inferred_apt_deps(
        name = "{}_apt_layers".format(name),
        base_packages = _BASE_APT_PACKAGES,
        deps = [binary],
        inferences = ["//shared:apt_inferences"],
    )

    optimized_layers(
        name = "{}_optimized".format(name),
        compress = "gzip",
        groups = [
            layer_group(
                name = "apt",
                overflow = "flatten",
                targets = [":{}_apt_layers".format(name)],
            ),
            layer_group(
                name = "interpreter",
                targets = ["//shared:python_interpreter"],
            ),
            layer_group(
                name = "pip",
                overflow = "flatten",
                targets = [":{}_pip".format(layers)],
            ),
            layer_group(
                name = "source",
                targets = [":{}_source".format(layers)],
            ),
        ],
        layer_budget = MAX_DOCKER_LAYERS,
        size_bytes_threshold = 1024 * 1024,
    )

    env_file(
        name = "{}_env".format(name),
        deps = [binary],
        inferences = ["//shared:env_inferences"],
    )

    oci_image(
        name = name,
        architecture = "amd64",
        entrypoint = ["/app"],
        env = ":{}_env".format(name),
        os = "linux",
        tars = [":{}_optimized".format(name)],
        visibility = ["//visibility:public"],
    )

def _binary_path(binary):
    label = native.package_relative_label(binary)
    return label.package + "/" + label.name if label.package else label.name
