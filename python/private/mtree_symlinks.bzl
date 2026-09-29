"""Preserve relative virtualenv symlinks for both Python rule families."""

def _preserve_mtree_symlinks_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".spec")
    transitive_inputs = [ctx.attr.mtree[DefaultInfo].files]
    for src in ctx.attr.srcs:
        transitive_inputs.append(src[DefaultInfo].files)
        transitive_inputs.append(src[DefaultInfo].default_runfiles.files)

    script = ctx.file._script

    # The toolchain interpreter rather than a bare `python3`: the latter is
    # resolved off the action PATH and is outside the ActionKey. This filter
    # stays on Python rather than gawk because it needs `os.readlink`.
    py_toolchain = ctx.attr.python_toolchain
    python3 = py_toolchain[platform_common.TemplateVariableInfo].variables["PYTHON3"]
    ctx.actions.run(
        executable = python3,
        inputs = depset(direct = [script], transitive = transitive_inputs),
        tools = [py_toolchain[DefaultInfo].files],
        outputs = [out],
        arguments = [script.path, ctx.file.mtree.path, out.path],
        mnemonic = "PyImageLayerPreserveSymlinks",
        progress_message = "Preserving symlinks in %s mtree" % ctx.label,
    )

    return [DefaultInfo(files = depset([out]))]

preserve_mtree_symlinks = rule(
    implementation = _preserve_mtree_symlinks_impl,
    attrs = {
        "_script": attr.label(default = Label("//python/private:mtree_symlinks.py"), allow_single_file = True),
        "mtree": attr.label(allow_single_file = True, mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "python_toolchain": attr.label(
            mandatory = True,
            cfg = "exec",
        ),
    },
)
