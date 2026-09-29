"""Run the assembled filesystem without registering aspect_rules_py toolchains."""

load("@aspect_bazel_lib//lib:tar.bzl", "tar_lib")

def _runtime_test_impl(ctx):
    toolchain = ctx.toolchains[tar_lib.toolchain_type]
    package_tars = ctx.attr.packages[DefaultInfo].files.to_list()
    if len(package_tars) != 3:
        fail("expected three distinct package layers, including the transitive six dependency")
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(script, """#!/usr/bin/env bash
set -euo pipefail
cd "$TEST_SRCDIR/$TEST_WORKSPACE"
"{tar}" -xf "{archive}" -C "$TEST_TMPDIR"
for package in {packages}; do
    "{tar}" -tf "$package" >> "$TEST_TMPDIR/package_entries"
done
[[ $(sort "$TEST_TMPDIR/package_entries" | uniq -d | wc -l) == 0 ]]
grep -F "/six.py" "$TEST_TMPDIR/package_entries"
set -a
source "{env}"
set +a
cd "$TEST_TMPDIR"
./app | grep -F 'standalone rules_python layers work'
""".format(tar = toolchain.tarinfo.binary.short_path, archive = ctx.file.archive.short_path, env = ctx.file.env.short_path, packages = " ".join([file.short_path for file in package_tars])), is_executable = True)
    return [DefaultInfo(executable = script, runfiles = ctx.runfiles(files = [ctx.file.archive, ctx.file.env] + package_tars, transitive_files = toolchain.default.files))]

runtime_test = rule(implementation = _runtime_test_impl, test = True, attrs = {
    "archive": attr.label(allow_single_file = True),
    "packages": attr.label(),
    "env": attr.label(allow_single_file = True),
}, toolchains = [tar_lib.toolchain_type])
