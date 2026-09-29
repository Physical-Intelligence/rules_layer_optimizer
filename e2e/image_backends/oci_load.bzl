"""Local Docker loading through the public rules_oci tarball API."""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_oci//oci:defs.bzl", "oci_tarball_rule")

def oci_load(name, image, repo_tags):
    """Load image archives from both the 1.x and 2.x output contracts.

    Args:
        name: Executable target name.
        image: Image to load into Docker.
        repo_tags: Local image tags.
    """
    write_file(
        name = name + "_tags",
        out = name + ".tags.txt",
        content = repo_tags,
    )
    oci_tarball_rule(name = name + "_archive", image = image, repo_tags = ":" + name + "_tags")
    _docker_load(name = name, archive = ":" + name + "_archive")

def _docker_load_impl(ctx):
    target = ctx.attr.archive
    groups = target[OutputGroupInfo] if OutputGroupInfo in target else None
    files = groups.tarball if groups and hasattr(groups, "tarball") else target[DefaultInfo].files
    archives = files.to_list()
    if len(archives) != 1:
        fail("expected one Docker archive")
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(script, """#!/usr/bin/env bash
set -euo pipefail
cd "${{RUNFILES_DIR:-$0.runfiles}}/{workspace}"
exec docker load --input "{archive}"
""".format(workspace = ctx.workspace_name, archive = archives[0].short_path), is_executable = True)
    return [DefaultInfo(executable = script, runfiles = ctx.runfiles(files = archives))]

_docker_load = rule(implementation = _docker_load_impl, executable = True, attrs = {"archive": attr.label(mandatory = True)})
