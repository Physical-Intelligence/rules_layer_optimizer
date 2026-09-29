"""Derive APT package size hints from rules_distroless lockfiles.

rules_distroless v2 locks record the compressed size of each resolved `.deb`.
The OCI optimizer consumes the package's compressed data tar instead, so the
lock value is an estimate rather than the exact output size. It is nevertheless
the closest stable input available during repository setup and avoids building
and measuring every package solely to maintain a second generated lockstep file.
"""

def parse_apt_lock_size_hints(lock_content, dependency_set, repository):
    """Returns size hints for one dependency set selected by an APT lock.

    Args:
        lock_content: String contents of a rules_distroless v2 JSON lockfile.
        dependency_set: Name of the lockfile dependency set to read.
        repository: Canonical Bazel repository name for that dependency set.

    Returns:
        Dict mapping exact canonical package labels to compressed `.deb`
        sizes in bytes.
    """
    lock = json.decode(lock_content)
    if type(lock) != "dict":
        fail("APT lock must contain a JSON object")

    dependency_sets = lock.get("dependency_sets")
    packages = lock.get("packages")
    if type(dependency_sets) != "dict" or type(packages) != "dict":
        fail("APT lock must contain object-valued dependency_sets and packages")

    size_hints = {}

    dependency_set_data = dependency_sets.get(dependency_set)
    if dependency_set_data == None:
        fail("APT lock has no dependency set named {}".format(dependency_set))

    selected_sets = dependency_set_data.get("sets")
    if type(selected_sets) != "dict" or not selected_sets:
        fail("APT lock dependency set {} must contain at least one package set".format(dependency_set))

    for selected_packages in selected_sets.values():
        if type(selected_packages) != "dict":
            fail("APT lock dependency set {} contains a non-object package set".format(dependency_set))
        for package_identity, version in selected_packages.items():
            package_key = "{}={}".format(package_identity, version)
            package = packages.get(package_key)
            if package == None:
                fail("APT lock selects {}, but has no matching package record".format(package_key))

            package_name = package.get("name")
            size = package.get("size")
            if not package_name or type(size) != "int" or size <= 0:
                fail("APT lock package {} must have a name and positive integer size".format(package_key))

            label = "@@{}//{}:{}".format(repository, package_name, package_name)
            previous_size = size_hints.get(label)
            size_hints[label] = max(previous_size or 0, size)

    return size_hints

def render_apt_size_hints_bzl(size_hints):
    """Renders an APT size-hint assignment for a generated Starlark module.

    Args:
        size_hints: Mapping of package labels to positive compressed-size hints.

    Returns:
        Starlark source defining the size table.
    """
    lines = ["APT_PACKAGE_SIZE_HINTS = {"]

    for package in sorted(size_hints.keys()):
        lines.append('    "{}": {},'.format(package, size_hints[package]))

    lines.append("}")
    return "\n".join(lines) + "\n"

def _apt_size_hints_repository_impl(rctx):
    size_hints = {}
    for index in range(len(rctx.attr.locks)):
        lock_hints = parse_apt_lock_size_hints(
            rctx.read(rctx.attr.locks[index]),
            rctx.attr.dependency_sets[index],
            rctx.attr.repositories[index].repo_name,
        )
        for package, size in lock_hints.items():
            previous_size = size_hints.get(package)
            size_hints[package] = max(previous_size or 0, size)

    rctx.file("BUILD.bazel", "exports_files([\"size_hints.bzl\"])\n")
    rctx.file("size_hints.bzl", render_apt_size_hints_bzl(size_hints))

apt_size_hints_repository = repository_rule(
    implementation = _apt_size_hints_repository_impl,
    attrs = {
        "dependency_sets": attr.string_list(),
        "locks": attr.label_list(allow_files = [".json"]),
        "repositories": attr.label_list(),
    },
)
