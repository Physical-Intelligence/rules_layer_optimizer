"""Tests for the per-wheel pip layer mtree filter."""

import os
import pathlib
import subprocess
import tempfile


def test_preserves_complete_site_packages_payload(tmp_path: pathlib.Path) -> None:
    src = tmp_path / "install"
    relative_paths = [
        "lib/python3.12/site-packages/example/__init__.py",
        "lib/python3.12/site-packages/example/__pycache__/cached.pyc",
        "lib/python3.12/site-packages/example/tests/test_example.py",
        "lib/python3.12/site-packages/example-1.0.dist-info/RECORD",
        "lib/python3.12/site-packages/nvidia/__init__.py",
        "lib/python3.12/not-site-packages/ignored.py",
    ]
    files = [src / relative_path for relative_path in relative_paths]
    for file in files:
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(file.name)

    filelist = tmp_path / "files.txt"
    filelist.write_text("\n".join(str(file) for file in reversed(files)) + "\n")
    output = tmp_path / "output.mtree"
    subprocess.run(
        [
            os.environ["GAWK"],
            "-v",
            f"filelist={filelist}",
            "-v",
            f"src={src}",
            "-v",
            "prefix=./app.runfiles/repo",
            "-v",
            f"out={output}",
            "-f",
            os.environ["PIP_LAYER_MTREE_AWK"],
        ],
        check=True,
    )

    expected_paths = [
        "lib/python3.12/site-packages/example-1.0.dist-info/RECORD",
        "lib/python3.12/site-packages/example/__init__.py",
        "lib/python3.12/site-packages/example/__pycache__/cached.pyc",
        "lib/python3.12/site-packages/example/tests/test_example.py",
        "lib/python3.12/site-packages/nvidia/__init__.py",
    ]
    assert output.read_text().splitlines() == ["#mtree"] + [
        f"./app.runfiles/repo/{path} type=file mode=0755 uid=0 gid=0 time=1672560000 contents={src}/{path}"
        for path in expected_paths
    ]


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        test_preserves_complete_site_packages_payload(pathlib.Path(directory))
