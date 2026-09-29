"""Prepare a deterministic source archive and verify standalone consumers."""

import argparse
import base64
import gzip
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess


def create_archive(
    root: pathlib.Path,
    output: pathlib.Path,
    repository: str | None = None,
    tag: str | None = None,
) -> pathlib.Path:
    ref = tag or "HEAD"
    module = subprocess.check_output(
        ["git", "show", ref + ":MODULE.bazel"], cwd=root
    ).decode()
    version = re.search(r'\bversion = "([^"]+)"', module)
    if version is None:
        raise ValueError("MODULE.bazel must declare a version")
    if tag is not None:
        if version[1] == "0.0.0" or not re.fullmatch(
            r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", version[1]
        ):
            raise ValueError("Set a release version in MODULE.bazel before releasing")
        if tag != "v" + version[1]:
            raise ValueError("Release tag must match the MODULE.bazel version")
    prefix = "rules_layer_optimizer-" + version[1]
    output.mkdir(parents=True, exist_ok=True)
    archive = output / (prefix + ".tar.gz")
    with (
        archive.open("wb") as raw,
        gzip.GzipFile(fileobj=raw, mode="wb", filename="", mtime=0) as compressed,
    ):
        compressed.write(
            subprocess.check_output(
                [
                    "git",
                    "-c",
                    "tar.umask=0022",
                    "archive",
                    "--format=tar",
                    "--prefix=" + prefix + "/",
                    ref,
                ],
                cwd=root,
            )
        )
    integrity = (
        "sha256-"
        + base64.b64encode(hashlib.sha256(archive.read_bytes()).digest()).decode()
    )
    url = archive.as_uri()
    if repository is not None:
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise ValueError("repository must be an owner/repo name")
        url = f"https://github.com/{repository}/releases/download/v{version[1]}/{archive.name}"
    source = {"url": url, "integrity": integrity, "strip_prefix": prefix}
    (output / "source.json").write_text(json.dumps(source, indent=2) + "\n")
    (output / "installation.MODULE.bazel").write_text(
        'bazel_dep(name = "rules_layer_optimizer", version = '
        + json.dumps(version[1])
        + ")\n"
        "archive_override(\n"
        '    module_name = "rules_layer_optimizer",\n'
        "    urls = [" + json.dumps(source["url"]) + "],\n"
        "    integrity = " + json.dumps(integrity) + ",\n"
        "    strip_prefix = " + json.dumps(prefix) + ",\n"
        ")\n"
    )
    return archive


def verify_archive(root: pathlib.Path, output: pathlib.Path) -> None:
    source = json.loads((output / "source.json").read_text())
    # Nested Bazel commands must not inherit the release tool's runfiles context.
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(("RUNFILES_", "JAVA_RUNFILES"))
    }
    for fixture in ("e2e/smoke", "examples"):
        consumer = output / "consumers" / fixture
        shutil.copytree(
            root / fixture,
            consumer,
            dirs_exist_ok=True,
            ignore=shutil.ignore_patterns("bazel-*"),
        )
        module = consumer / "MODULE.bazel"
        replacement = 'archive_override(\n    module_name = "rules_layer_optimizer",\n'
        for name, value in [
            ("urls", [(output / (source["strip_prefix"] + ".tar.gz")).as_uri()]),
            ("integrity", source["integrity"]),
            ("strip_prefix", source["strip_prefix"]),
        ]:
            replacement += f"    {name} = {json.dumps(value)},\n"
        replacement += ")"
        contents, count = re.subn(
            r'local_path_override\(\s*module_name = "rules_layer_optimizer",\s*path = "[^"]+",\s*\)',
            replacement,
            module.read_text(),
        )
        if count != 1:
            raise ValueError(f"Expected one checkout override in {fixture}")
        module.write_text(contents)
        rc = consumer / ".bazelrc"
        rc.write_text(
            (root / ".bazelrc").read_text()
            + "\n"
            + "\n".join(
                line
                for line in rc.read_text().splitlines()
                if not line.startswith("import ")
            )
            + "\n"
        )
        subprocess.run(
            ["bazel", "test", "//...", "--test_output=errors"],
            cwd=consumer,
            env=env,
            check=True,
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--verify", action="store_true")
    parser.add_argument(
        "--repository", help="GitHub owner/repo for release download URLs"
    )
    parser.add_argument("--tag", help="Release tag to validate against MODULE.bazel")
    args = parser.parse_args()
    root = pathlib.Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])
    output = args.output.resolve()
    if output.is_relative_to(root):
        parser.error("--output must be outside the checkout")
    archive = create_archive(root, output, args.repository, args.tag)
    print(f"Prepared {archive}", flush=True)
    if args.verify:
        verify_archive(root, output)


if __name__ == "__main__":
    main()
