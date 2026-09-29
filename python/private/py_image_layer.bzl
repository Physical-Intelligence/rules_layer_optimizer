"""Split aspect_rules_py runfiles into reusable package and caller-defined source layers."""

load("@aspect_bazel_lib//lib:tar.bzl", "mtree_spec", "tar")
load("//python/private:mtree_symlinks.bzl", "preserve_mtree_symlinks")
load("//python/private:pip_layer_aspect.bzl", "pip_layer_aspect")
load("//python/private:pip_layer_reducer.bzl", "make_pip_layer_reducer")
load("//python/private:repository_paths.bzl", "module_extension_repo_pattern")

pip_layer_reducer = make_pip_layer_reducer(pip_layer_aspect)

def py_image_layer(
        name,
        binary,
        interpreter_tar,
        python_toolchain,
        strip_prefix,
        source_layers = {},
        exclude_patterns = [],
        compress = "zstd",
        tar_args = [],
        compute_unused_inputs = 0,
        **kwargs):
    """Create package, interpreter, and partitioned source tars under /app.

    Args:
        name: Prefix for public outputs; the target itself contains all layers.
        binary: aspect_rules_py py_binary.
        interpreter_tar: Caller-built interpreter tar with the binary's runfiles layout.
        python_toolchain: Exec-config target exposing PYTHON3 and interpreter files.
        strip_prefix: Literal binary runfiles prefix, e.g. my/package/app.
        source_layers: Ordered mapping from layer names to lists of AWK path regexes.
            The first matching layer owns each entry; unmatched entries stay in source.
        exclude_patterns: Path regexes to omit, for files packaged separately by callers.
        compress: Compression for all source tars.
        tar_args: Additional arguments for source tar actions.
        compute_unused_inputs: Passed to source tar rules.
        **kwargs: Common attributes applied to generated targets. Helpers stay private.
    """
    private = dict(kwargs, visibility = ["//visibility:private"])
    mtree_spec(name = name + "_mtree", srcs = [binary], **private)
    preserve_mtree_symlinks(
        name = name + "_symlinks",
        srcs = [binary],
        mtree = ":" + name + "_mtree",
        python_toolchain = python_toolchain,
        **private
    )
    _split_source(
        name = name + "_split",
        mtree = ":" + name + "_symlinks",
        strip_prefix = strip_prefix,
        source_layers = source_layers,
        exclude_patterns = exclude_patterns,
        **private
    )
    pip_layer_reducer(name = name + "_pip", deps = [binary], **kwargs)
    native.alias(name = name + "_interpreter", actual = interpreter_tar, **kwargs)
    for part in ["source"] + ["source_" + layer for layer in source_layers]:
        native.filegroup(
            name = name + "_" + part + "_mtree",
            srcs = [":" + name + "_split"],
            output_group = part,
            **private
        )
        tar(
            name = name + "_" + part,
            srcs = [binary],
            mtree = ":" + name + "_" + part + "_mtree",
            compress = compress,
            args = (["--options=zstd:threads=0"] if compress == "zstd" else []) + tar_args,
            compute_unused_inputs = compute_unused_inputs,
            **kwargs
        )
    native.filegroup(
        name = name + "_source_deps",
        srcs = [":" + name + "_source_" + layer for layer in source_layers],
        **kwargs
    )
    native.filegroup(
        name = name,
        srcs = [":" + name + "_" + part for part in ["pip", "interpreter", "source_deps", "source"]],
        **kwargs
    )

def _split_source_impl(ctx):
    if not ctx.attr.strip_prefix:
        fail("strip_prefix must be the non-empty binary path")
    outputs = {"source": ctx.actions.declare_file(ctx.label.name + ".source.mtree")}

    # Package and interpreter entries are supplied by their dedicated producers.
    excluded = [
        "[.]whl$",
        "dist-info/(RECORD|INSTALLER|WHEEL|REQUESTED)$",
        "/__pycache__(/|$)",
        "^[.]/app[.]runfiles/?$",
        "[.]runfiles/" + module_extension_repo_pattern("rules_python", "python"),
        "[.]runfiles/" + module_extension_repo_pattern("rules_python", "pip"),
        "[.]runfiles/" + module_extension_repo_pattern("aspect_rules_py", "python_interpreters"),
        "[.]runfiles/" + module_extension_repo_pattern("aspect_rules_py", "uv"),
    ] + ctx.attr.exclude_patterns
    rows = [["-", pattern] for pattern in excluded]
    for name, patterns in ctx.attr.source_layers.items():
        if not name or name == "deps" or any([c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_" for c in name.elems()]):
            fail("source layer names must use letters, numbers, or underscores and cannot be 'deps'")
        out = ctx.actions.declare_file(ctx.label.name + ".source_" + name + ".mtree")
        outputs["source_" + name] = out
        rows.append([out.path, ""])
        rows.extend([[out.path, pattern] for pattern in patterns])
    for _, pattern in rows:
        if "\t" in pattern or "\n" in pattern:
            fail("source layer patterns cannot contain tabs or newlines")
    config = ctx.actions.declare_file(ctx.label.name + ".patterns")
    ctx.actions.write(config, "".join([destination + "\t" + pattern + "\n" for destination, pattern in rows]))
    ctx.actions.run(
        executable = ctx.executable._awk,
        inputs = [ctx.file.mtree, config, ctx.file._script],
        outputs = outputs.values(),
        arguments = ["-v", "prefix=" + ctx.attr.strip_prefix, "-v", "source=" + outputs["source"].path, "-f", ctx.file._script.path, config.path, ctx.file.mtree.path],
        mnemonic = "PythonSourceLayers",
    )
    return [OutputGroupInfo(**{name: depset([file]) for name, file in outputs.items()})]

_split_source = rule(
    implementation = _split_source_impl,
    attrs = {
        "mtree": attr.label(allow_single_file = True, mandatory = True),
        "strip_prefix": attr.string(mandatory = True),
        "source_layers": attr.string_list_dict(),
        "exclude_patterns": attr.string_list(),
        "_awk": attr.label(default = Label("@gawk"), executable = True, cfg = "exec"),
        "_script": attr.label(default = Label("//python/private:split_source.awk"), allow_single_file = True),
    },
)
