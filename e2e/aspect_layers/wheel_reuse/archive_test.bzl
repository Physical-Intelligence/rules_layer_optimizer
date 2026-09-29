"""Inspect real archives using the same declared tar toolchain as the library."""

load("@aspect_bazel_lib//lib:tar.bzl", "tar_lib")

def _archive_test_impl(ctx):
    toolchain = ctx.toolchains[tar_lib.toolchain_type]
    tar = toolchain.tarinfo.binary
    archives = ctx.attr.archive[DefaultInfo].files.to_list()
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    lines = ["#!/usr/bin/env bash", "set -euo pipefail", 'cd "$TEST_SRCDIR/$TEST_WORKSPACE"', ': > "$TEST_TMPDIR/entries"']
    for archive in archives:
        lines.append('"{}" -tf "{}" >> "$TEST_TMPDIR/entries"'.format(tar.short_path, archive.short_path))
    for expected in ctx.attr.contains:
        lines.append("grep -F -- '{}' \"$TEST_TMPDIR/entries\"".format(expected))
    for excluded in ctx.attr.excludes:
        lines.append("if grep -F -- '{}' \"$TEST_TMPDIR/entries\"; then exit 1; fi".format(excluded))
    ctx.actions.write(script, "\n".join(lines) + "\n", is_executable = True)
    return [DefaultInfo(executable = script, runfiles = ctx.runfiles(files = archives, transitive_files = toolchain.default.files))]

archive_test = rule(implementation = _archive_test_impl, test = True, attrs = {"archive": attr.label(allow_files = True), "contains": attr.string_list(), "excludes": attr.string_list()}, toolchains = [tar_lib.toolchain_type])
