"""Infer OCI image environment variables from a target's dependency graph.

Callers register mappings with `env_inference` rather than a global dict. Each
image calls `env_file`, which depends on those inference targets,
walks the binary with an aspect, and includes only the mappings that matched.
"""

load("@rules_python//python:defs.bzl", "PyInfo")
load("//inference/private:dependency_inference.bzl", "dependency_graph_aspect", "dependency_identities", "inference_matches", "validate_inference_triggers")
load("//inference/private:env.bzl", "DEFAULT_ENV_SEPARATORS", "merge_env")

EnvInferenceInfo = provider(
    "One environment inference mapping: graph labels that trigger environment variables.",
    fields = {
        "env": "Environment variables to add when a trigger matches.",
        "for_deps": "Exact Bazel labels that trigger this mapping.",
        "for_keys": "Opaque adapter-defined keys that trigger this mapping.",
    },
)

EnvInferenceBundleInfo = provider(
    "Flattened env_inference entries so an image can depend on one bundle target.",
    fields = {
        "entries": "List of structs with for_deps and env.",
    },
)

def _env_inference_rule_impl(ctx):
    return [EnvInferenceInfo(
        env = ctx.attr.env,
        for_deps = ctx.attr.for_deps,
        for_keys = ctx.attr.for_keys,
    )]

_env_inference_rule = rule(
    implementation = _env_inference_rule_impl,
    doc = "Register environment variables to add when `for_deps` appear in a target graph.",
    attrs = {
        "env": attr.string_dict(
            mandatory = True,
            doc = "Environment variables to add when this inference matches.",
        ),
        "for_deps": attr.string_list(
            mandatory = True,
            doc = "Exact Bazel labels that trigger this mapping.",
        ),
        "for_keys": attr.string_list(mandatory = True),
    },
)

def env_inference(
        name,
        env,
        for_deps = [],
        for_keys = [],
        **kwargs):
    """Register one environment inference and validate its trigger labels.

    Args:
        name: Name of the environment inference target.
        for_deps: Bazel labels that trigger this inference. Use python:inference.bzl for logical pip-package matching.
        for_keys: Additional opaque keys supplied by a dependency adapter.
        env: Environment variables to add when any trigger appears in the graph.
        **kwargs: Additional attributes for the environment inference target.
    """
    triggers = _inference_triggers(for_deps)
    _env_inference_rule(
        name = name,
        env = env,
        for_deps = triggers.labels,
        for_keys = for_keys,
        **kwargs
    )
    validate_inference_triggers(
        name = name + "_for_deps_test",
        for_deps = for_deps,
    )

def _env_inference_bundle_impl(ctx):
    return [EnvInferenceBundleInfo(entries = [
        struct(
            env = inference[EnvInferenceInfo].env,
            for_deps = tuple(inference[EnvInferenceInfo].for_deps),
            for_keys = tuple(inference[EnvInferenceInfo].for_keys),
        )
        for inference in ctx.attr.inferences
    ])]

env_inference_bundle = rule(
    implementation = _env_inference_bundle_impl,
    doc = "Collect env_inference targets so an image can depend on one label.",
    attrs = {
        "inferences": attr.label_list(
            mandatory = True,
            providers = [EnvInferenceInfo],
            doc = "env_inference targets to include.",
        ),
    },
)

def _env_file_impl(ctx):
    """Collect inferred environment variables and merge explicit variables."""
    env = dict(ctx.attr.base_env)

    seen = _seen_labels(ctx)
    for entry in _inference_entries(ctx):
        if inference_matches(entry.for_deps + entry.for_keys, seen):
            env = merge_env(env, entry.env, ctx.attr.env_separators)

    env = merge_env(env, ctx.attr.extra_env, ctx.attr.env_separators)
    pythonpath = _pythonpath_from_imports(ctx.attr.pythonpath_deps, ctx.attr.runfiles_root)
    if pythonpath:
        env = merge_env(env, {"PYTHONPATH": pythonpath}, ctx.attr.env_separators)

    serialized = "".join(["{}={}\n".format(k, v) for k, v in env.items()])

    out = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.write(
        output = out,
        content = serialized,
    )
    return [DefaultInfo(files = depset([out]))]

def make_env_file(dependency_aspects = []):
    """Create an inference rule with additional dependency-identity aspects."""
    return rule(
        implementation = _env_file_impl,
        attrs = {
            "base_env": attr.string_dict(),
            "env_separators": attr.string_dict(default = DEFAULT_ENV_SEPARATORS),
            "deps": attr.label_list(aspects = [dependency_graph_aspect] + dependency_aspects),
            "extra_env": attr.string_dict(),
            "inferences": attr.label_list(providers = [EnvInferenceBundleInfo]),
            "pythonpath_deps": attr.label_list(),
            "runfiles_root": attr.string(default = "/app.runfiles"),
        },
    )

env_file = make_env_file()

def _pythonpath_from_imports(deps, runfiles_root):
    imports = depset(transitive = [
        target[PyInfo].imports
        for target in deps
        if PyInfo in target
    ])

    # Keep non-wheel import roots too: source-only external py_library repos
    # are exposed through PyInfo.imports but do not live
    # under site-packages.
    paths = [
        "{}/{}".format(runfiles_root, import_path)
        for import_path in imports.to_list()
        if import_path
    ]
    return ":".join(paths)

def _seen_labels(ctx):
    return dependency_identities(ctx.attr.deps)

def _inference_triggers(for_deps):
    return struct(labels = [str(native.package_relative_label(dep)) for dep in for_deps], keys = [])

def _inference_entries(ctx):
    entries = []
    for inference in ctx.attr.inferences:
        entries.extend(inference[EnvInferenceBundleInfo].entries)
    return entries
