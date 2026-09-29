"""rules_python package layers and runfiles splitting."""

load("@aspect_bazel_lib//lib:tar.bzl", "mtree_spec", "tar", "tar_lib")
load("@oci_image_inference_config//:config.bzl", "DEPENDENCY_ATTRIBUTES")
load("@rules_python//python:py_runtime_info.bzl", "PyRuntimeInfo")
load("//python/private:mtree_symlinks.bzl", "preserve_mtree_symlinks")
load("//python/private:pip_deps.bzl", "PipDepsInfo", "merge_pip_deps")
load("//python/private:pip_layer_artifacts.bzl", "PipLayerArtifactsInfo", "merge_pip_package_tars")
load("//python/private:pip_layer_reducer.bzl", "make_pip_layer_reducer")
load("//python/private:pip_utils.bzl", "pip_package_size_hint")
load("//python/private:rules_python_wheel.bzl", "wheel_files", "wheel_package")

WheelFilesInfo = provider("Files already packaged into wheel layers.", fields = {"files": "Wheel runtime files, excluding source and interpreter files."})

def py_image_layer(name, binary, strip_prefix, compress = "gzip", **kwargs):
    """Split a rules_python binary into interpreter, reusable pip, and source tars.

    Args:
        name: Prefix for the generated targets.
        binary: rules_python py_binary with an in-build interpreter.
        strip_prefix: Binary runfiles prefix, e.g. my/package/app.
        compress: Source and interpreter compression.
        **kwargs: Common target attributes (visibility, tags, etc.).
    """
    private = dict(kwargs, visibility = ["//visibility:private"])
    mtree_spec(name = name + "_mtree", srcs = [binary], **private)
    preserve_mtree_symlinks(
        name = name + "_symlinks",
        srcs = [binary],
        mtree = ":" + name + "_mtree",
        python_toolchain = Label("@rules_python//python:current_py_toolchain"),
        **private
    )
    _split_runfiles(
        name = name + "_split",
        binary = binary,
        mtree = ":" + name + "_symlinks",
        strip_prefix = strip_prefix,
        **private
    )
    pip_layer_reducer(name = name + "_pip", deps = [binary], **kwargs)
    for part in ["source", "interpreter"]:
        native.filegroup(name = name + "_" + part + "_mtree", srcs = [":" + name + "_split"], output_group = part, **private)
        tar(
            name = name + "_" + part,
            srcs = [binary],
            mtree = ":" + name + "_" + part + "_mtree",
            compress = compress,
            **kwargs
        )
    native.filegroup(name = name, srcs = [":" + name + "_" + part for part in ["interpreter", "pip", "source"]], **kwargs)

def _package_aspect_impl(target, ctx):
    packages = {}
    sizes = {}
    sources = {}
    transitive_files = []
    for attribute in DEPENDENCY_ATTRIBUTES:
        value = getattr(ctx.rule.attr, attribute, None)
        for dep in (value if type(value) == "list" else [value]) if value else []:
            if PipLayerArtifactsInfo in dep:
                merge_pip_package_tars(packages, dep[PipLayerArtifactsInfo].package_tars, target.label)
            if PipDepsInfo in dep:
                merge_pip_deps(sizes, sources, dep[PipDepsInfo], target.label)
            if WheelFilesInfo in dep:
                transitive_files.append(dep[WheelFilesInfo].files)
    files = []
    package = wheel_package(ctx)
    if package:
        size = pip_package_size_hint(package)
        if size <= 0:
            fail("no positive pip size hint configured for package " + package)
        source = "@@" + target.label.repo_name
        merge_pip_deps(
            sizes,
            sources,
            PipDepsInfo(
                pip_deps = {package: size},
                pip_sources = {package: source},
            ),
            target.label,
        )
        files = wheel_files(target)
        mtree = ctx.actions.declare_file("pip_tars/" + package + ".mtree")
        rows = ["#mtree"]
        for file in sorted(files, key = lambda f: f.short_path):
            if file.is_directory:
                fail("rules_python wheel tree artifacts are not supported: " + file.path)
            path = file.short_path.removeprefix("../")
            rows.append("./app.runfiles/{} type=file mode=0755 uid=0 gid=0 time=0 contents={}".format(_escape(path), _escape(file.path)))
        ctx.actions.write(mtree, "\n".join(rows) + "\n")
        out = ctx.actions.declare_file("pip_tars/" + package + ".tar.gz")
        toolchain = ctx.toolchains[tar_lib.toolchain_type]
        args = ctx.actions.args()
        args.add_all(["--create", "--gzip", "--options=gzip:!timestamp", "--file", out.path, "@" + mtree.path])
        ctx.actions.run(
            executable = toolchain.tarinfo.binary,
            inputs = files + [mtree],
            tools = [toolchain.default.files],
            outputs = [out],
            arguments = [args],
            env = toolchain.tarinfo.default_env,
            mnemonic = "RulesPythonPackageTar",
        )
        merge_pip_package_tars(packages, {package: struct(tar = out, size_bytes = size, source = source)}, target.label)
    return [
        PipLayerArtifactsInfo(package_tars = packages),
        PipDepsInfo(pip_deps = sizes, pip_sources = sources),
        WheelFilesInfo(files = depset(files, transitive = transitive_files)),
    ]

_package_aspect = aspect(
    implementation = _package_aspect_impl,
    attr_aspects = DEPENDENCY_ATTRIBUTES,
    provides = [PipLayerArtifactsInfo, PipDepsInfo, WheelFilesInfo],
    toolchains = [tar_lib.toolchain_type],
)
pip_layer_reducer = make_pip_layer_reducer(_package_aspect)

def _split_runfiles_impl(ctx):
    runtime = ctx.attr.binary[PyRuntimeInfo]
    if runtime.interpreter == None:
        fail("rules_python layers require an in-build Python interpreter")
    classification = ctx.actions.declare_file(ctx.label.name + ".files")
    rows = ["pip " + _escape(file.path) for file in ctx.attr.binary[WheelFilesInfo].files.to_list()]
    rows.extend(["interpreter " + _escape(file.path) for file in runtime.files.to_list() + [runtime.interpreter]])
    ctx.actions.write(classification, "\n".join(rows) + "\n")
    source = ctx.actions.declare_file(ctx.label.name + ".source.mtree")
    interpreter = ctx.actions.declare_file(ctx.label.name + ".interpreter.mtree")
    ctx.actions.run(
        executable = ctx.executable._awk,
        inputs = [ctx.file.mtree, classification, ctx.file._script],
        outputs = [source, interpreter],
        arguments = [
            "-v",
            "classification=" + classification.path,
            "-v",
            "prefix=" + ctx.attr.strip_prefix,
            "-v",
            "source=" + source.path,
            "-v",
            "interpreter=" + interpreter.path,
            "-f",
            ctx.file._script.path,
            ctx.file.mtree.path,
        ],
        mnemonic = "RulesPythonSplitRunfiles",
    )
    return [OutputGroupInfo(source = depset([source]), interpreter = depset([interpreter]))]

_split_runfiles = rule(implementation = _split_runfiles_impl, attrs = {
    "binary": attr.label(mandatory = True, aspects = [_package_aspect], providers = [PyRuntimeInfo]),
    "mtree": attr.label(mandatory = True, allow_single_file = True),
    "strip_prefix": attr.string(mandatory = True),
    "_awk": attr.label(default = Label("@gawk"), executable = True, cfg = "exec"),
    "_script": attr.label(default = Label("//python/private:rules_python_split.awk"), allow_single_file = True),
})

def _escape(value):
    return value.replace("\\", "\\134").replace(" ", "\\040").replace("\t", "\\011").replace("\n", "\\012").replace("#", "\\043")
