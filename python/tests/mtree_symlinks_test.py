"""Exercise mtree escaping and the virtualenv symlink boundary."""

import os
import pathlib
import subprocess
import sys
import tempfile


def test_relative_links(tmp_path: pathlib.Path) -> None:
    link = tmp_path / "python link"
    link.symlink_to("../lib/a b#c\\d")
    content = str(link).replace(" ", r"\040")
    row = f"./app.runfiles/app.venv/bin/python type=file nlink=1 content={content} mode=0755"
    output = _run(tmp_path, [row])
    assert output == [
        r"./app.runfiles/app.venv/bin/python type=link mode=0755 link=../lib/a\040b\043c\134d"
    ]


def test_only_relative_virtualenv_links_are_preserved(tmp_path: pathlib.Path) -> None:
    relative = tmp_path / "relative"
    relative.symlink_to("target")
    absolute = tmp_path / "absolute"
    absolute.symlink_to("/usr/bin/python3")
    regular = tmp_path / "file"
    regular.write_text("payload")
    rows = [
        f"./app.runfiles/app_venv/bin/python type=file content={relative}",
        f"./app.runfiles/app.venv/bin/absolute type=file content={absolute}",
        f"./app.runfiles/app.venv/_wheels/pkg/file type=file content={relative}",
        f"./app.runfiles/source/file type=file content={relative}",
        f"./app.runfiles/app.venv/bin/regular type=file content={regular}",
        "# comment",
    ]
    assert _run(tmp_path, rows) == [
        "./app.runfiles/app_venv/bin/python type=link link=target",
        *rows[1:],
    ]


def _run(tmp_path: pathlib.Path, rows: list[str]) -> list[str]:
    source = tmp_path / "input.spec"
    output = tmp_path / "output.spec"
    source.write_text("\n".join(rows) + "\n")
    subprocess.run(
        [sys.executable, os.environ["FILTER"], str(source), str(output)], check=True
    )
    return output.read_text().splitlines()


if __name__ == "__main__":
    for test in (
        test_relative_links,
        test_only_relative_virtualenv_links_are_preserved,
    ):
        with tempfile.TemporaryDirectory() as directory:
            test(pathlib.Path(directory))
