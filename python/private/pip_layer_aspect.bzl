"""Aspect that declares per-package pip tars at the pip target's namespace.

`pip_layer_aspect` walks the binary's pip closure and, at each
`whl_install` boundary, declares a zstd tar via bsdtar over an mtree spec
built by a constant gawk filter. Both actions take only the wheel
TreeArtifact and declared tools as inputs, so two binaries that both consume
`@pip//numpy` resolve to the same Bazel actions and the tar is built once.

Consumers (`pip_layer_reducer` in `py_image_layer.bzl`) read the
`PipLayerArtifactsInfo` provider and bucket the tars by `size_bytes`
(from the generated OCI inference configuration) into heavy / light layers.
"""

load("@aspect_bazel_lib//lib:tar.bzl", "tar_lib")
load("@oci_image_inference_config//:config.bzl", "DEPENDENCY_ATTRIBUTES")
load("//python/private:aspect_rules_py.bzl", "selected_wheel_filename", "wheel_identity", "wheel_package", "wheel_record", "wheel_runfiles_prefix")
load("//python/private:pip_deps.bzl", "PipDepsInfo", "merge_pip_deps")
load("//python/private:pip_utils.bzl", "pip_package_size_hint", "pip_wheel_size_hint", "sorted_by_size_hint")

_GAWK = Label("@gawk")
_PIP_LAYER_MTREE_AWK = Label("//python/private:pip_layer_mtree.awk")

PipLayerArtifactsInfo = provider(
    doc = "Per-package pip tars produced by pip_layer_aspect.",
    fields = {
        "package_tars": "Dict mapping normalized distribution name -> struct(tar=File, size_bytes=int, group=str|None, source=str).",
    },
)

def merge_pip_package_tars(package_tars, additions, owner):
    """Merge package tars, rejecting ambiguous distribution identities."""
    for package, info in additions.items():
        _validate_package_source(package_tars, package, info.source, owner)
        package_tars[package] = info

_KEEP_KINDS = ["py_library", "py_binary", "whl_install", "alias"]

# The mtree filter applied to each wheel TreeArtifact before bsdtar packs it
# lives in pip_layer_mtree.awk.

def _bsdtar_compress_flags(algorithm, level):
    """Maps `(algorithm, level)` to the corresponding bsdtar CLI flags.

    `level=None` selects the algorithm's default compression level. Fails
    fast on an unsupported algorithm — the tier definition is the only
    place this can come from, so a typo there should be a build error
    rather than silently producing an uncompressed tar.

    `threads=0` for zstd lets libarchive auto-select one worker per CPU,
    which roughly halves wall time on the heavy CUDA tars (~80 MB+) on
    multi-core builders. Gzip is left single-threaded — libarchive's
    pigz integration isn't reliably available.
    """
    if algorithm == "zstd":
        opts = ["threads=0"]
        if level != None:
            opts.append("compression-level=%s" % level)
        return "--options=zstd:%s --zstd" % ",".join(opts)
    if algorithm == "gzip":
        return "--gzip" if level == None else "--options=gzip:compression-level=%s --gzip" % level
    fail("Unsupported tar compression algorithm %r" % algorithm)

def _ext_for(algorithm):
    """Returns the conventional file extension (including leading dot) for `algorithm`."""
    if algorithm == "zstd":
        return ".tar.zst"
    if algorithm == "gzip":
        return ".tar.gz"
    fail("Unsupported tar compression algorithm %r" % algorithm)

def _declare_pip_tar(target, ctx, normalized_label, algorithm, level, basename):
    """Declares the per-package tar action for `pkg_name` and returns the output File.

    The actions' inputs are deliberately constrained to the wheel TreeArtifact
    + bsdtar + gawk + the constant mtree filter. The output path is
    `pip_tars/<basename>.tar.{zst,gz}` under the *aspect target's* analysis
    context — so two binaries that share `@pip//<pkg_name>` resolve to the
    same Bazel action key and the tar is built once, then disk- and
    remote-cached across the monorepo.

    Returns None if the target doesn't carry a wheel TreeArtifact (e.g.
    aliases / py_library wrappers — the aspect propagates through `deps`,
    `src`, and `actual` instead).
    """
    wheel = wheel_record(target)
    if not wheel:
        return None
    tree_artifact = wheel.install_tree
    prefix = wheel_runfiles_prefix(wheel)
    out = ctx.actions.declare_file("pip_tars/" + basename + _ext_for(algorithm))

    bsdtar = ctx.toolchains[tar_lib.toolchain_type]

    # Bazel writes the TreeArtifact expansion to a file, one path per line, so
    # enumerating the wheel needs no host `find`. The gawk and bsdtar actions
    # below run declared tools, which are part of the ActionKey.
    filelist = ctx.actions.declare_file("pip_tars/" + basename + ".files")
    filelist_args = ctx.actions.args()
    filelist_args.add_all([tree_artifact], expand_directories = True)
    filelist_args.set_param_file_format("multiline")
    ctx.actions.write(output = filelist, content = filelist_args)

    awk_file = ctx.file._awk_script

    mtree = ctx.actions.declare_file("pip_tars/" + basename + ".mtree")
    mtree_args = ctx.actions.args()
    mtree_args.add("-v", "filelist=" + filelist.path)
    mtree_args.add("-v", "src=" + tree_artifact.path)
    mtree_args.add("-v", "prefix=" + prefix)
    mtree_args.add("-v", "out=" + mtree.path)
    mtree_args.add("-f", awk_file.path)
    ctx.actions.run(
        executable = ctx.executable._awk,
        outputs = [mtree],
        inputs = [filelist, awk_file],
        arguments = [mtree_args],
        # Byte-wise collation, so mtree row order cannot depend on the
        # builder's locale.
        env = {"LC_ALL": "C"},
        mnemonic = "PipPackageMtree",
        progress_message = "Building pip layer mtree for %s" % normalized_label,
    )

    tar_args = ctx.actions.args()
    tar_args.add("--create")
    for flag in _bsdtar_compress_flags(algorithm, level).split(" "):
        if flag:
            tar_args.add(flag)
    tar_args.add("--file", out)
    tar_args.add("@" + mtree.path)
    ctx.actions.run(
        executable = bsdtar.tarinfo.binary,
        outputs = [out],
        inputs = depset([tree_artifact, mtree]),
        tools = [bsdtar.default.files],
        arguments = [tar_args],
        env = bsdtar.tarinfo.default_env,
        mnemonic = "PipPackageTar",
        progress_message = "Building pip layer tar for %s" % normalized_label,
    )
    return out

def _propagate_from_attr(ctx, attr_name, package_tars, pip_deps, pip_sources):
    """Merges providers from `ctx.rule.attr.<attr_name>` deps into the running dicts.

    Used by both aspect impls to fold transitive `PipLayerArtifactsInfo` /
    `PipDepsInfo` from the configured traversal attributes into this target's
    accumulated state. Handles both
    list-valued and scalar-valued attributes, and is a no-op if the
    attribute is missing.

    Mutates `package_tars` and `pip_deps` in place.
    """
    attr_value = getattr(ctx.rule.attr, attr_name, None)
    if attr_value == None:
        return
    values = attr_value if type(attr_value) == "list" else [attr_value]
    for dep in values:
        if PipLayerArtifactsInfo in dep:
            merge_pip_package_tars(package_tars, dep[PipLayerArtifactsInfo].package_tars, ctx.label)
        if PipDepsInfo in dep:
            merge_pip_deps(pip_deps, pip_sources, dep[PipDepsInfo], ctx.label)

def _pip_layer_aspect_impl(target, ctx):
    """Emits a zstd tar for every `whl_install` reached.

    Every real pip package gets `pip_tars/<pkg>.tar.zst` at the wheel's own
    namespace, action-deduped across binaries. Consumed by `pip_layer_reducer`
    in `py_image_layer.bzl`, which buckets by size hint into heavy / light.
    """
    package_tars = {}
    pip_deps = {}
    pip_sources = {}

    for attr_name in DEPENDENCY_ATTRIBUTES:
        _propagate_from_attr(ctx, attr_name, package_tars, pip_deps, pip_sources)

    if ctx.rule.kind in _KEEP_KINDS:
        pkg_name = wheel_package(target.label)
        if pkg_name:
            normalized = pkg_name
            source = wheel_identity(target.label)
            merge_pip_deps(
                pip_deps,
                pip_sources,
                PipDepsInfo(
                    pip_deps = {pkg_name: pip_package_size_hint(pkg_name)},
                    pip_sources = {pkg_name: source},
                    sorted_pip_deps = [pkg_name],
                ),
                target.label,
            )

            # This lookup intentionally happens before we declare the tar. The
            # reducer must classify layers during analysis, so the size travels
            # as provider metadata next to the tar File rather than as a
            # generated output file that would be unreadable until execution.
            size_bytes = pip_wheel_size_hint(pkg_name, selected_wheel_filename(ctx))

            # whl_install is the only kind that owns the wheel TreeArtifact.
            # Aliases / py_library wrappers reach the same package via attr
            # propagation, so we only emit one action per (package, version).
            if ctx.rule.kind == "whl_install":
                _validate_package_source(package_tars, normalized, source, target.label)
            if ctx.rule.kind == "whl_install" and normalized not in package_tars:
                tar_file = _declare_pip_tar(target, ctx, normalized, "zstd", None, pkg_name)
                if tar_file:
                    package_tars[normalized] = struct(
                        tar = tar_file,
                        size_bytes = size_bytes,
                        group = None,
                        source = source,
                    )

    return [
        PipLayerArtifactsInfo(package_tars = package_tars),
        PipDepsInfo(
            pip_deps = pip_deps,
            pip_sources = pip_sources,
            sorted_pip_deps = sorted_by_size_hint(pip_deps),
        ),
    ]

pip_layer_aspect = aspect(
    implementation = _pip_layer_aspect_impl,
    attr_aspects = DEPENDENCY_ATTRIBUTES,
    attrs = {
        "_awk": attr.label(default = _GAWK, cfg = "exec", executable = True),
        "_awk_script": attr.label(
            allow_single_file = True,
            default = _PIP_LAYER_MTREE_AWK,
        ),
    },
    provides = [PipDepsInfo, PipLayerArtifactsInfo],
    toolchains = [tar_lib.toolchain_type],
)

def _validate_package_source(package_tars, package, source, owner):
    previous = package_tars.get(package)
    if previous != None and previous.source != source:
        fail("{} reaches multiple wheels for pip distribution '{}': {} and {}".format(
            owner,
            package,
            previous.source,
            source,
        ))
