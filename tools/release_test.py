"""Exercise committed archive contents, release tags, and consumer metadata."""

import base64
import hashlib
import json
import os
import pathlib
import subprocess
import tarfile
import tempfile

from tools.release import create_archive


def test_source_archive(tmp_path: pathlib.Path) -> None:
    root = tmp_path / "source"
    root.mkdir()
    module = b'module(name = "rules_layer_optimizer", version = "0.1.0")\n'
    _repository(
        root,
        {
            "MODULE.bazel": ("100644", module),
            ".gitattributes": ("100644", b"ignored export-ignore\n"),
            "ignored": ("100644", b"excluded"),
            "script.sh": ("100755", b"#!/bin/sh\nexit 0\n"),
            "alias.sh": ("120000", b"script.sh"),
        },
    )
    (root / "MODULE.bazel").write_text('module(version = "dirty")')
    (root / "untracked").write_text("excluded")
    first = create_archive(root, tmp_path / "first")
    second = create_archive(
        root,
        tmp_path / "second",
        "Physical-Intelligence/rules_layer_optimizer",
        "v0.1.0",
    )
    assert first.read_bytes() == second.read_bytes()
    prefix = "rules_layer_optimizer-0.1.0"
    with tarfile.open(first) as archive:
        contents = {}
        for member in archive.getmembers():
            if member.isdir():
                continue
            file = archive.extractfile(member) if member.isfile() else None
            contents[member.name.removeprefix(prefix + "/")] = (
                member.mode,
                member.linkname,
                file.read() if file else None,
            )
        assert contents == {
            ".gitattributes": (0o644, "", b"ignored export-ignore\n"),
            "MODULE.bazel": (0o644, "", module),
            "script.sh": (0o755, "", b"#!/bin/sh\nexit 0\n"),
            "alias.sh": (0o777, "script.sh", None),
        }, contents
    integrity = (
        "sha256-"
        + base64.b64encode(hashlib.sha256(first.read_bytes()).digest()).decode()
    )
    for archive, url in [
        (first, first.as_uri()),
        (
            second,
            "https://github.com/Physical-Intelligence/rules_layer_optimizer/releases/download/v0.1.0/"
            + second.name,
        ),
    ]:
        assert json.loads((archive.parent / "source.json").read_text()) == {
            "url": url,
            "integrity": integrity,
            "strip_prefix": prefix,
        }
        assert (archive.parent / "installation.MODULE.bazel").read_text() == (
            'bazel_dep(name = "rules_layer_optimizer", version = "0.1.0")\n'
            "archive_override(\n"
            '    module_name = "rules_layer_optimizer",\n'
            f'    urls = ["{url}"],\n'
            f'    integrity = "{integrity}",\n'
            f'    strip_prefix = "{prefix}",\n'
            ")\n"
        )


def test_release_tag(tmp_path: pathlib.Path) -> None:
    for index, (version, tag, expected) in enumerate(
        [
            ("0.2.0", "v0.1.0", "Release tag must match the MODULE.bazel version"),
            (
                "0.0.0",
                "v0.1.0",
                "Set a release version in MODULE.bazel before releasing",
            ),
            (
                "invalid",
                "v0.1.0",
                "Set a release version in MODULE.bazel before releasing",
            ),
        ]
    ):
        root = tmp_path / str(index)
        root.mkdir()
        _repository(
            root,
            {"MODULE.bazel": ("100644", f'module(version = "{version}")'.encode())},
        )
        output = root / "rejected"
        try:
            create_archive(root, output, tag=tag)
        except ValueError as error:
            assert str(error) == expected
        else:
            raise AssertionError("Invalid release tag was accepted")
        assert not output.exists()


def _repository(root: pathlib.Path, files: dict[str, tuple[str, bytes]]) -> None:
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    for path, (mode, data) in files.items():
        blob = (
            subprocess.check_output(
                ["git", "hash-object", "-w", "--stdin"], input=data, cwd=root
            )
            .decode()
            .strip()
        )
        subprocess.run(
            ["git", "update-index", "--add", "--cacheinfo", mode, blob, path],
            cwd=root,
            check=True,
        )
    tree = subprocess.check_output(["git", "write-tree"], cwd=root).decode().strip()
    commit = (
        subprocess.check_output(
            [
                "git",
                "-c",
                "user.name=Archive test",
                "-c",
                "user.email=test@example.invalid",
                "commit-tree",
                tree,
                "-m",
                "Archive fixture",
            ],
            cwd=root,
            env={
                **os.environ,
                "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z",
                "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z",
            },
        )
        .decode()
        .strip()
    )
    subprocess.run(["git", "update-ref", "HEAD", commit], cwd=root, check=True)
    subprocess.run(
        ["git", "update-ref", "refs/tags/v0.1.0", commit], cwd=root, check=True
    )


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        test_source_archive(pathlib.Path(directory))
        test_release_tag(pathlib.Path(directory))
