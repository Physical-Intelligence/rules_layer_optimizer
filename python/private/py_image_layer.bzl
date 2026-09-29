"""Produce reusable Python package, interpreter, native, and source layers.

The default path emits public `<name>_pip`, `<name>_source`,
`<name>_source_deps`, and `<name>_pyo3` targets. The pip target provides
LayerTarsInfo and SizeHintInfo for the shared layer optimizer.

The caller supplies an interpreter tar, an execution toolchain, and source
bucket policy. Package layers use the stable /app.runfiles layout.
"""

load("@aspect_bazel_lib//lib:tar.bzl", "mtree_spec", "tar", "tar_lib")
load("@aspect_bazel_lib//lib:transitions.bzl", "platform_transition_filegroup")

# buildifier: disable=bzl-visibility
load("//layers/private:layer_groups.bzl", "LayerTarsInfo", "SizeHintInfo")
load("//python/private:pip_deps.bzl", "PipDepsInfo", "merge_pip_deps")
load("//python/private:pip_layer_aspect.bzl", "PipLayerArtifactsInfo", "merge_pip_package_tars", "pip_layer_aspect")
load("//python/private:pip_utils.bzl", "sorted_by_size_hint")
load("//python/private:pyo3_layer_aspect.bzl", "Pyo3ArtifactsInfo", "pyo3_layer_aspect")
load("//python/private:repository_paths.bzl", "module_extension_repo_pattern")
load("//python/private:source_dep_buckets.bzl", "source_dep_bucket_matches_file")

_EXCLUDE_PYO3_AWK = Label("//python/private:exclude_pyo3.awk")
_GAWK = Label("@gawk")

def _pyo3_layer_reducer_impl(ctx):
    artifacts = {}
    for dep in ctx.attr.deps:
        if Pyo3ArtifactsInfo in dep:
            artifacts.update(dep[Pyo3ArtifactsInfo].artifacts)

    binary_runfiles = {
        file.short_path: True
        for dep in ctx.attr.deps
        for file in dep[DefaultInfo].default_runfiles.files.to_list()
    }
    tars = []
    bsdtar = ctx.toolchains[tar_lib.toolchain_type]
    for label, files in sorted(artifacts.items()):
        included_files = [file for file in files if file.short_path in binary_runfiles]
        if not included_files:
            continue
        tar_file = ctx.actions.declare_file("pyo3_tars/{}.tar.zst".format(_safe_layer_name(label)))
        root = ctx.attr.root[1:] if ctx.attr.root.startswith("/") else ctx.attr.root
        mtree_rows = [
            "./{root}.runfiles/_main/{path} type=file mode=0755 uid=0 gid=0 time=1672560000 contents={contents}".format(
                root = root,
                path = file.short_path,
                contents = file.path,
            )
            for file in included_files
        ]

        # The mtree is fully determined at analysis time, so write it directly and
        # invoke bsdtar as the executable. Going through a shell would pull in an
        # undeclared `mktemp` and `/bin/bash`, neither of which is in the ActionKey.
        mtree_file = ctx.actions.declare_file("pyo3_tars/{}.mtree".format(_safe_layer_name(label)))
        ctx.actions.write(
            output = mtree_file,
            content = "\n".join(["#mtree"] + mtree_rows) + "\n",
        )
        args = ctx.actions.args()
        args.add("--create")
        args.add("--options=zstd:threads=0")
        args.add("--zstd")
        args.add("--file", tar_file)
        args.add("@" + mtree_file.path)
        ctx.actions.run(
            executable = bsdtar.tarinfo.binary,
            outputs = [tar_file],
            inputs = depset(included_files + [mtree_file]),
            tools = [bsdtar.default.files],
            arguments = [args],
            env = bsdtar.tarinfo.default_env,
            mnemonic = "Pyo3ExtensionTar",
            progress_message = "Building PyO3 layer tar for %s" % label,
        )
        tars.append(tar_file)

    return [
        DefaultInfo(files = depset(tars)),
        LayerTarsInfo(tars = tars),
        Pyo3ArtifactsInfo(artifacts = artifacts),
    ]

pyo3_layer_reducer = rule(
    doc = "Builds one OCI layer tar per PyO3 extension in a Python dependency closure.",
    implementation = _pyo3_layer_reducer_impl,
    attrs = {
        "deps": attr.label_list(aspects = [pyo3_layer_aspect]),
        "root": attr.string(default = "/app"),
    },
    provides = [DefaultInfo, LayerTarsInfo, Pyo3ArtifactsInfo],
    toolchains = [tar_lib.toolchain_type],
)

def _safe_layer_name(label):
    name = label
    for char in ["@", "/", ":", "+", "~", ".", "-"]:
        name = name.replace(char, "_")
    return name.strip("_")

def _pip_layer_reducer_impl(ctx):
    """Reduces `PipLayerArtifactsInfo` from `pip_layer_aspect` into size hints.

    The aspect emits one tar per pip package at that package's own
    namespace (action-deduped across binaries); this rule walks the
    transitive provider and exposes every package tar with its generated size
    hint. The optimizer owns the threshold decision so it can raise the
    effective cutoff when the final image-wide layer budget would be exceeded.

    Candidate tars are sorted largest-first so they appear first in the
    consuming image when retained as individual layers. That also makes the
    smallest candidates the first ones folded into the flat pip layer when
    either the static threshold or dynamic layer budget requires it.
    """
    package_tars = {}
    pip_deps = {}
    pip_sources = {}
    for dep in ctx.attr.deps:
        if PipLayerArtifactsInfo in dep:
            merge_pip_package_tars(package_tars, dep[PipLayerArtifactsInfo].package_tars, ctx.label)
        if PipDepsInfo in dep:
            merge_pip_deps(pip_deps, pip_sources, dep[PipDepsInfo], ctx.label)

    candidate_entries = []
    file_sizes = {}
    for normalized_label, info in sorted(package_tars.items()):
        candidate_entries.append((info.size_bytes, normalized_label, info.tar))
        file_sizes[info.tar] = info.size_bytes

    candidate_entries = sorted(candidate_entries, key = lambda x: (-x[0], x[1]))
    candidate_files = [tar_file for _, _, tar_file in candidate_entries]

    return [
        DefaultInfo(files = depset(candidate_files)),
        LayerTarsInfo(tars = candidate_files),
        SizeHintInfo(sizes = file_sizes),
        PipLayerArtifactsInfo(package_tars = package_tars),
        PipDepsInfo(
            pip_deps = pip_deps,
            pip_sources = pip_sources,
            sorted_pip_deps = sorted_by_size_hint(pip_deps),
        ),
    ]

pip_layer_reducer = rule(
    doc = "Collects per-package pip tars (from `pip_layer_aspect`) and exposes size hints.",
    implementation = _pip_layer_reducer_impl,
    attrs = {
        "deps": attr.label_list(aspects = [pip_layer_aspect]),
    },
    provides = [DefaultInfo, LayerTarsInfo, SizeHintInfo, PipLayerArtifactsInfo, PipDepsInfo],
)

# Match the canonical repository spellings used by supported Python toolchains.
_INTERPRETER_REGEX = r"\\.runfiles/({}|{}).*".format(
    module_extension_repo_pattern("rules_python", "python"),
    module_extension_repo_pattern("aspect_rules_py", "python_interpreters", "python_"),
)
_PACKAGES_REGEX = r"\\.runfiles/({}|{}).*".format(
    module_extension_repo_pattern("rules_python", "pip"),
    module_extension_repo_pattern("aspect_rules_py", "uv", "whl_install__"),
)
_ASPECT_RULES_PY_UV_REGEX = module_extension_repo_pattern("aspect_rules_py", "uv")

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
            generated_venv_entry = re.search(r"/[.][^/]*(?:[.]venv|_venv)/", entry)
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

_preserve_mtree_symlinks = rule(
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

def _split_mtree_source_impl(ctx):
    """Extracts the source-only mtree spec from the binary's runfiles.

    All pip paths (`whl_install__` / `aspect_rules_py++uv+`) and Python
    interpreter paths are dropped: pip is owned by `pip_layer_aspect`'s
    per-package tars; interpreter is replaced by the static
    `interpreter_tar`. What's left is the first-party Python source.

    `strip_prefix` typically contains unescaped `/` (e.g.
    `examples/application`); awk's `/.../` regex literal
    ends at the first unescaped `/`, so we escape every `/` before
    splicing the prefix into `sub(...)`.
    """
    source_out = ctx.actions.declare_file(ctx.label.name + ".source.spec")
    strip_prefix_re_escaped = ctx.attr.strip_prefix.replace("/", "\\/")

    # Caller-supplied runfiles subtrees to drop from the source layer (e.g. a bundled tool
    # like gcloud that is neither pip nor first-party source, and is delivered as its own
    # layer). Matched against the whole (post-strip_prefix) mtree line, like the pip regexes.
    extra_excludes = "".join([
        '\n    if ($0 ~ "{re}") next'.format(re = re)
        for re in ctx.attr.extra_source_excludes
    ])

    awk = """\
BEGIN {{
    print "#mtree" > "{source}"
}}
{{
    if ($1 ~ "\\\\.whl$") next
    if ($1 ~ "dist-info/(RECORD|INSTALLER|WHEEL|REQUESTED)$") next
    if ($1 ~ "/__pycache__(/|$)") next

    sub(/^{strip_prefix_re}/, ".{root}")

    # The interpreter tar already declares app.runfiles without a leading "./".
    # Drop the source-layer directory entry so the no-optimizations flatten path
    # does not produce a Docker-normalized duplicate of that top-level directory.
    if ($1 == ".{root}.runfiles/" || $1 == ".{root}.runfiles") next

    if ($0 ~ "{interpreter_re}") next
    if ($0 ~ "{packages_re}") next
    if ($1 ~ "{aspect_rules_py_uv_re}") next{extra_excludes}

    print $0 >> "{source}"
}}
""".format(
        source = source_out.path,
        strip_prefix_re = strip_prefix_re_escaped,
        root = ctx.attr.root,
        interpreter_re = _INTERPRETER_REGEX,
        packages_re = _PACKAGES_REGEX,
        aspect_rules_py_uv_re = _ASPECT_RULES_PY_UV_REGEX,
        extra_excludes = extra_excludes,
    )

    # The program writes its own output via `print ... > "{source}"`, so no shell
    # redirect is needed and gawk can be the action executable. A bare `awk` here
    # would be resolved off the action PATH and left out of the ActionKey.
    awk_file = ctx.actions.declare_file(ctx.label.name + ".source.awk")
    ctx.actions.write(output = awk_file, content = awk)
    ctx.actions.run(
        executable = ctx.executable._awk,
        outputs = [source_out],
        inputs = [ctx.file.mtree, awk_file],
        arguments = ["-f", awk_file.path, ctx.file.mtree.path],
        mnemonic = "PyImageLayerSourceSplit",
        progress_message = "Extracting %s source mtree" % ctx.label,
    )

    return [DefaultInfo(files = depset([source_out]))]

_split_mtree_source = rule(
    implementation = _split_mtree_source_impl,
    attrs = {
        "mtree": attr.label(allow_single_file = True, mandatory = True),
        "strip_prefix": attr.string(default = ""),
        "root": attr.string(default = "/"),
        "extra_source_excludes": attr.string_list(default = []),
        "_awk": attr.label(default = _GAWK, cfg = "exec", executable = True),
    },
)

def _exclude_pyo3_from_mtree_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".spec")
    root = ctx.attr.root[1:] if ctx.attr.root.startswith("/") else ctx.attr.root
    excluded_entries = [
        "./{}.runfiles/_main/{}".format(root, file.short_path)
        for file in _pyo3_artifacts(ctx.attr.binary)
    ]

    # Bare `python3` (like bare `awk`) is resolved off the action PATH and is not
    # part of the ActionKey; gawk is a declared exec-config tool. The exclusion set
    # travels in a file rather than argv so a large PyO3 closure cannot overflow it.
    excluded_file = ctx.actions.declare_file(ctx.label.name + ".pyo3_excluded.txt")
    ctx.actions.write(
        output = excluded_file,
        content = "".join([entry + "\n" for entry in excluded_entries]),
    )
    awk_file = ctx.file._awk_script
    ctx.actions.run(
        executable = ctx.executable._awk,
        inputs = [ctx.file.mtree, excluded_file, awk_file],
        outputs = [out],
        arguments = [
            "-v",
            "excluded_file=" + excluded_file.path,
            "-v",
            "out=" + out.path,
            "-f",
            awk_file.path,
            ctx.file.mtree.path,
        ],
        mnemonic = "PyImageExcludePyo3",
        progress_message = "Excluding separately layered PyO3 extensions from %s" % ctx.label,
    )
    return [DefaultInfo(files = depset([out]))]

_exclude_pyo3_from_mtree = rule(
    implementation = _exclude_pyo3_from_mtree_impl,
    attrs = {
        "binary": attr.label(aspects = [pyo3_layer_aspect], mandatory = True),
        "mtree": attr.label(allow_single_file = True, mandatory = True),
        "root": attr.string(default = "/app"),
        "_awk": attr.label(default = _GAWK, cfg = "exec", executable = True),
        "_awk_script": attr.label(
            allow_single_file = True,
            default = _EXCLUDE_PYO3_AWK,
        ),
    },
)

def _non_pyo3_native_extension_files_impl(ctx):
    pyo3_paths = {file.short_path: True for file in _pyo3_artifacts(ctx.attr.binary)}
    files = [
        file
        for file in ctx.attr.binary[DefaultInfo].default_runfiles.files.to_list()
        if _native_extensions_source_dep_matches(file) and file.short_path not in pyo3_paths
    ]
    return [DefaultInfo(files = depset(files))]

_non_pyo3_native_extension_files = rule(
    implementation = _non_pyo3_native_extension_files_impl,
    attrs = {
        "binary": attr.label(aspects = [pyo3_layer_aspect], mandatory = True),
    },
)

def _native_extensions_source_dep_matches(file):
    path = file.short_path
    return _is_first_party_runfile_artifact(path) and path.endswith(".so")

def py_image_layer(
        name,
        binary,
        interpreter_tar,
        python_toolchain,
        source_dep_buckets,
        root = "/app",
        strip_prefix = "",
        compress = "zstd",
        platform = None,
        tar_args = [],
        compute_unused_inputs = 0,
        extra_source_excludes = [],
        source_dep_runfiles_patterns = {},
        **kwargs):
    """OCI image layers from a `py_binary`. See module docstring for paths.

    Args:
        name: base name for generated targets.
        binary: a `py_binary` target.
        interpreter_tar: tar target whose content replaces the runfiles-derived
            interpreter layer.
        python_toolchain: exec-config target exposing the `PYTHON3` template
            variable and interpreter files.
        source_dep_buckets: Explicit source-dependency bucket policies created
            with `source_dep_bucket`.
        root: Shared image root. Must be `/app` to match reusable wheel layers.
        strip_prefix: regex-escaped path prefix to strip before applying `root`.
        compress: tar compression for the source layer.
        platform: optional `platform_transition_filegroup` target.
        tar_args: extra args passed to the underlying `tar` rule.
        compute_unused_inputs: passed through to the `tar` rule.
        extra_source_excludes: (data-driven path only) list of regexes; runfiles mtree lines
            matching any of them are dropped from the source layer. Use to peel a bundled tool
            (e.g. gcloud) out of source when it is delivered as its own layer.
        source_dep_runfiles_patterns: (data-driven path only) mapping from source-dependency
            layer suffix to awk regexes matching normalized mtree rows. These extend the
            automatic source-dependency buckets for stable non-pip runfiles.
        **kwargs: applied to all generated targets.

    Returns:
        A list of layer target labels (in `oci_image.tars=` order).
    """
    if root != "/app":
        fail("py_image_layer requires root='/app' to share package layers across binaries")

    tags = kwargs.pop("tags", []) + ["manual", "no-remote-cache"]

    return _expand_data_driven(
        name = name,
        binary = binary,
        root = root,
        strip_prefix = strip_prefix,
        compress = compress,
        platform = platform,
        interpreter_tar = interpreter_tar,
        python_toolchain = python_toolchain,
        tar_args = tar_args,
        compute_unused_inputs = compute_unused_inputs,
        extra_source_excludes = extra_source_excludes,
        source_dep_runfiles_patterns = source_dep_runfiles_patterns,
        source_dep_buckets = source_dep_buckets,
        tags = tags,
        **kwargs
    )

def _expand_data_driven(
        *,
        name,
        binary,
        root,
        strip_prefix,
        compress,
        platform,
        interpreter_tar,
        python_toolchain,
        tar_args,
        compute_unused_inputs,
        extra_source_excludes,
        source_dep_runfiles_patterns,
        source_dep_buckets,
        tags,
        **kwargs):
    """Default expansion path: data-driven pip candidates + source mtree.

    Three artifacts:
      1. `_{name}_pip` — `_pip_layer_reducer` target carrying
         pip package tars and `SizeHintInfo` for `optimize_layers` to
         consume. The optimizer applies the configured threshold after it has
         the full image-local layer group set available.
      2. `_{name}_pyo3` — one tar per PyO3 binding reached through the
         binary's Python dependency closure.
      3. `_{name}_source` — single tar built from the binary's runfiles
         with pip + interpreter paths stripped (pip is owned by (1);
         interpreter is replaced by the static `interpreter_tar`).

    Public aliases expose the candidate targets without depending on internal
    helper names. The composite target includes every generated layer.
    """
    pip_target = "_{}_pip".format(name)
    pip_layer_reducer(
        name = pip_target,
        deps = [binary],
        tags = tags,
        **kwargs
    )

    pyo3_target = "_{}_pyo3".format(name)
    pyo3_layer_reducer(
        name = pyo3_target,
        deps = [binary],
        root = root,
        tags = tags,
        **kwargs
    )

    mtree_spec(
        name = name + ".manifest.raw",
        srcs = [binary],
        tags = tags,
        **kwargs
    )

    _preserve_mtree_symlinks(
        name = name + ".manifest",
        mtree = name + ".manifest.raw",
        python_toolchain = python_toolchain,
        srcs = [binary],
        # Every input is declared and the venv symlink targets are fixed at
        # analysis time, so this action is reproducible across hosts. It is
        # neither large nor cheap to rebuild, so it keeps the cache.
        tags = [tag for tag in tags if tag != "no-remote-cache"],
        **kwargs
    )

    source_dep_entries = _source_dep_pattern_entries(source_dep_runfiles_patterns, source_dep_buckets)
    source_dep_excludes = []
    for entry in source_dep_entries:
        source_dep_excludes = source_dep_excludes + entry.patterns

    source_split = "_{}_source_split".format(name)
    _split_mtree_source(
        name = source_split,
        mtree = name + ".manifest",
        strip_prefix = strip_prefix,
        root = root,
        extra_source_excludes = extra_source_excludes + source_dep_excludes,
        tags = tags,
        **kwargs
    )

    source_deps = "_{}_source_deps".format(name)
    source_dep_targets = []
    source_dep_names = []
    assigned_source_dep_matches = []
    for entry in source_dep_entries:
        split_name = entry.name
        patterns = entry.patterns
        source_dep_targets.append(_source_dep_layer(
            image_name = name,
            binary = binary,
            split_name = split_name,
            patterns = patterns,
            exclude_patterns = assigned_source_dep_matches,
            strip_prefix = strip_prefix,
            root = root,
            compress = compress,
            compute_unused_inputs = compute_unused_inputs,
            tar_args = tar_args,
            tags = tags,
            **kwargs
        ))
        source_dep_names.append(split_name)
        assigned_source_dep_matches = assigned_source_dep_matches + patterns
    _select_source_dep_tars(
        name = source_deps,
        binary = binary,
        bucket_names = source_dep_names,
        bucket_specs = [entry.spec for entry in source_dep_entries],
        bucket_tars = source_dep_targets,
        explicit_bucket_names = [split_name for split_name, _ in _explicit_source_dep_pattern_entries(source_dep_runfiles_patterns)],
        tags = tags,
        **kwargs
    )

    source_tar = "_{}_source".format(name)

    # libarchive's parallel zstd: `threads=0` auto-selects one worker per CPU.
    # Source tars are single large files, so parallel compression pays off on
    # warm-incremental rebuilds where this action is the critical path.
    parallel_zstd_args = ["--options=zstd:threads=0"] if compress == "zstd" else []
    tar(
        name = source_tar,
        srcs = [binary],
        mtree = source_split,
        compress = compress,
        compute_unused_inputs = compute_unused_inputs,
        args = parallel_zstd_args + tar_args,
        tags = tags,
        **kwargs
    )

    # Bottom → top of the OCI stack: per-package pip tars first (stable),
    # interpreter (static), source last (changes most).
    no_src_srcs = [
        ":" + pip_target,
        interpreter_tar,
        ":" + pyo3_target,
        ":" + source_deps,
    ]
    only_src_srcs = [":" + source_tar]
    all_srcs = no_src_srcs + only_src_srcs

    for suffix, target in [("pip", pip_target), ("pyo3", pyo3_target), ("source_deps", source_deps), ("source", source_tar)]:
        native.alias(name = name + "_" + suffix, actual = ":" + target, tags = tags, **kwargs)
    return _emit_filegroups(name, all_srcs, no_src_srcs, only_src_srcs, platform, tags, **kwargs)

def _source_dep_layer(
        *,
        image_name,
        binary,
        split_name,
        patterns,
        exclude_patterns,
        strip_prefix,
        root,
        compress,
        compute_unused_inputs,
        tar_args,
        tags,
        **kwargs):
    target_suffix = "_" + split_name
    source_deps_match = _joined_awk_regex(patterns).replace("$", "$$")
    exclude_filter = ""
    if exclude_patterns:
        exclude_filter = '    if ($$0 ~ "{match}") next\n'.format(
            match = _joined_awk_regex(exclude_patterns).replace("$", "$$"),
        )
    spec_target = "_{name}_source_deps{suffix}_spec".format(name = image_name, suffix = target_suffix)
    native.genrule(
        name = spec_target,
        srcs = [":{name}.manifest".format(name = image_name)],
        outs = ["{name}_source_deps{suffix}.spec".format(name = image_name, suffix = target_suffix)],
        # A declared gawk rather than a bare `awk`: the host awk is
        # resolved off the action PATH and is not part of the ActionKey. The
        # program writes to stdout, so the genrule redirects it into `$@`.
        cmd = """\
$(execpath {gawk}) 'BEGIN {{ print "#mtree" }} {{
    if ($$1 ~ "\\\\.whl$$") next
    if ($$1 ~ "dist-info/(RECORD|INSTALLER|WHEEL|REQUESTED)$$") next
    if ($$1 ~ "/__pycache__(/|$$)") next
    sub(/^{strip_prefix}/, ".{root}")
{exclude_filter}    if ($$0 ~ "{match}") print
}}' $< > $@
""".format(
            exclude_filter = exclude_filter,
            strip_prefix = strip_prefix.replace("/", "\\/"),
            root = root,
            match = source_deps_match,
            gawk = _GAWK,
        ),
        tools = [_GAWK],
        tags = tags,
        **kwargs
    )
    mtree_target = ":" + spec_target
    tar_srcs = [binary]
    if split_name == "native_extensions":
        filtered_spec_target = spec_target + "_without_pyo3"
        _exclude_pyo3_from_mtree(
            name = filtered_spec_target,
            binary = binary,
            mtree = mtree_target,
            root = root,
            tags = tags,
            **kwargs
        )
        mtree_target = ":" + filtered_spec_target
        native_files_target = "_{name}_source_deps_native_extension_files".format(name = image_name)
        _non_pyo3_native_extension_files(
            name = native_files_target,
            binary = binary,
            tags = tags,
            **kwargs
        )
        tar_srcs = [":" + native_files_target]
    tar_target = "_{name}_source_deps{suffix}".format(name = image_name, suffix = target_suffix)
    tar(
        name = tar_target,
        srcs = tar_srcs,
        mtree = mtree_target,
        compress = compress,
        compute_unused_inputs = compute_unused_inputs,
        args = tar_args,
        tags = tags,
        **kwargs
    )
    return ":" + tar_target

def _select_source_dep_tars_impl(ctx):
    if len(ctx.attr.bucket_names) != len(ctx.attr.bucket_tars) or len(ctx.attr.bucket_names) != len(ctx.attr.bucket_specs):
        fail("bucket_names, bucket_specs, and bucket_tars must have matching lengths")

    explicit = {name: True for name in ctx.attr.explicit_bucket_names}
    buckets = [json.decode(spec) for spec in ctx.attr.bucket_specs]
    matched = {}
    for i in range(len(ctx.attr.bucket_names)):
        name = ctx.attr.bucket_names[i]
        bucket = _bucket_from_json(buckets[i])
        matched[name] = name in explicit or (bucket.include_if_executable and ctx.attr.binary[DefaultInfo].files_to_run.executable != None)

    pyo3_paths = {file.short_path: True for file in _pyo3_artifacts(ctx.attr.binary)}
    for file in ctx.attr.binary[DefaultInfo].default_runfiles.files.to_list():
        if _is_source_dropped_path(file.short_path):
            continue
        for i in range(len(ctx.attr.bucket_names)):
            name = ctx.attr.bucket_names[i]
            bucket = _bucket_from_json(buckets[i])
            if bucket.exclude_pyo3 and file.short_path in pyo3_paths:
                continue
            if not matched[name] and source_dep_bucket_matches_file(bucket, file):
                matched[name] = True
                break

    selected = []
    for i in range(len(ctx.attr.bucket_names)):
        if matched[ctx.attr.bucket_names[i]]:
            selected.extend(ctx.attr.bucket_tars[i][DefaultInfo].files.to_list())

    return [
        DefaultInfo(files = depset(selected)),
        LayerTarsInfo(tars = selected),
    ]

_select_source_dep_tars = rule(
    implementation = _select_source_dep_tars_impl,
    attrs = {
        "binary": attr.label(aspects = [pyo3_layer_aspect], mandatory = True),
        "bucket_names": attr.string_list(mandatory = True),
        "bucket_specs": attr.string_list(mandatory = True),
        "bucket_tars": attr.label_list(allow_files = True, mandatory = True),
        "explicit_bucket_names": attr.string_list(default = []),
    },
    provides = [DefaultInfo, LayerTarsInfo],
)

def _source_dep_pattern_entries(patterns_by_split, source_dep_buckets):
    explicit_entries = _explicit_source_dep_pattern_entries(patterns_by_split)
    merged = {}
    order = []
    specs = {}
    for bucket in source_dep_buckets:
        if bucket.name in merged:
            fail("duplicate source dependency bucket '{}'".format(bucket.name))
        merged[bucket.name] = list(bucket.patterns)
        specs[bucket.name] = _bucket_json(bucket)
        order.append(bucket.name)
    for split_name, patterns in explicit_entries:
        if split_name not in merged:
            order.append(split_name)
            merged[split_name] = []
            specs[split_name] = "{}"
        merged[split_name] = merged[split_name] + patterns
    return [
        struct(name = split_name, patterns = merged[split_name], spec = specs[split_name])
        for split_name in order
    ]

def _explicit_source_dep_pattern_entries(patterns_by_split):
    if type(patterns_by_split) != "dict":
        fail("source_dep_runfiles_patterns must be a dict from split name to list of awk regexes")

    entries = []
    for split_name in sorted(patterns_by_split.keys()):
        _validate_source_dep_split_name(split_name)
        patterns = patterns_by_split[split_name]
        if type(patterns) != "list":
            fail("source_dep_runfiles_patterns['{}'] must be a list".format(split_name))
        if not patterns:
            fail("source_dep_runfiles_patterns['{}'] must not be empty".format(split_name))
        entries.append((split_name, patterns))
    return entries

def _bucket_json(bucket):
    return json.encode({
        "exclude_pyo3": bucket.exclude_pyo3,
        "first_party_only": bucket.first_party_only,
        "include_if_executable": bucket.include_if_executable,
        "matchers": [
            {"kind": matcher.kind, "value": matcher.value, "values": list(matcher.values)}
            for matcher in bucket.matchers
        ],
    })

def _bucket_from_json(bucket):
    return struct(
        exclude_pyo3 = bucket.get("exclude_pyo3", False),
        first_party_only = bucket.get("first_party_only", False),
        include_if_executable = bucket.get("include_if_executable", False),
        matchers = tuple([
            struct(kind = matcher["kind"], value = matcher["value"], values = tuple(matcher["values"]))
            for matcher in bucket.get("matchers", [])
        ]),
    )

def _validate_source_dep_split_name(split_name):
    if not split_name:
        fail("source dependency split names must be non-empty")
    for char in split_name.elems():
        if char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
            fail("source dependency split name '{}' must contain only letters, numbers, and underscores".format(split_name))

def _is_first_party_runfile_artifact(path):
    return not path.startswith("../") and not path.startswith("external/") and "/external/" not in path

def _is_source_dropped_path(path):
    return (
        path.endswith(".whl") or
        path.endswith("dist-info/RECORD") or
        path.endswith("dist-info/INSTALLER") or
        path.endswith("dist-info/WHEEL") or
        path.endswith("dist-info/REQUESTED") or
        "/__pycache__/" in path or
        path.endswith("/__pycache__")
    )

def _joined_awk_regex(patterns):
    return "(" + "|".join(patterns) + ")"

def _pyo3_artifacts(target):
    if Pyo3ArtifactsInfo not in target:
        return []
    return [
        file
        for _, files in sorted(target[Pyo3ArtifactsInfo].artifacts.items())
        for file in files
    ]

def _emit_filegroups(name, all_srcs, no_src_srcs, only_src_srcs, platform, tags, **kwargs):
    """Emits compatibility filegroups: `<name>`, `<name>_no_src`, `<name>_only_src`.

    Falls back to `platform_transition_filegroup` when `platform` is set so
    cross-platform image builds get the right runfiles transitioned in.
    The default, source-only, and dependency-only filegroups produce the
    same target shape.
    """
    if platform:
        platform_transition_filegroup(
            name = name,
            srcs = all_srcs,
            target_platform = platform,
            tags = tags,
            **kwargs
        )
        platform_transition_filegroup(
            name = name + "_no_src",
            srcs = no_src_srcs,
            target_platform = platform,
            tags = tags,
            **kwargs
        )
        platform_transition_filegroup(
            name = name + "_only_src",
            srcs = only_src_srcs,
            target_platform = platform,
            tags = tags,
            **kwargs
        )
    else:
        native.filegroup(
            name = name,
            srcs = all_srcs,
            tags = tags,
            **kwargs
        )
        native.filegroup(
            name = name + "_no_src",
            srcs = no_src_srcs,
            tags = tags,
            **kwargs
        )
        native.filegroup(
            name = name + "_only_src",
            srcs = only_src_srcs,
            tags = tags,
            **kwargs
        )
    return all_srcs
