"""Preserve relative virtualenv symlinks for both Python rule families."""

_PRESERVE_SYMLINKS_PY = """\
import os
import re
import sys

mtree, out = sys.argv[1:3]
with open(mtree, encoding="utf-8") as src, open(out, "w", encoding="utf-8") as dst:
    for line in src:
        row = line.rstrip("\\n")
        if " type=file " in row and " content=" in row:
            entry = row.partition(" ")[0]
            before, after = row.rsplit(" content=", 1)
            content, separator, rest = after.partition(" ")
            link = None
            generated_venv_entry = re.search(r"/[^/]*(?:[.]venv|_venv)/", entry)
            if generated_venv_entry and "/_wheels/" not in entry:
                link = os.readlink(content) if os.path.islink(content) else None
            if link and not os.path.isabs(link):
                before = before.replace(" type=file ", " type=link ", 1)
                before = re.sub(r" nlink=[^ ]+", "", before, count=1)
                row = f"{before} link={link}"
                if separator:
                    row = f"{row} {rest}"
        dst.write(row + "\\n")"""

def _preserve_mtree_symlinks_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".spec")
    transitive_inputs = [ctx.attr.mtree[DefaultInfo].files]
    for src in ctx.attr.srcs:
        transitive_inputs.append(src[DefaultInfo].files)
        transitive_inputs.append(src[DefaultInfo].default_runfiles.files)

    script = ctx.actions.declare_file(ctx.label.name + ".preserve_symlinks.py")
    ctx.actions.write(output = script, content = _PRESERVE_SYMLINKS_PY)

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
        "mtree": attr.label(allow_single_file = True, mandatory = True),
        "srcs": attr.label_list(allow_files = True),
        "python_toolchain": attr.label(
            mandatory = True,
            cfg = "exec",
        ),
    },
)
