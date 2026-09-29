"""Verify runfiles partitioning without dropping source or duplicating wheels."""

import os
import pathlib
import subprocess
import tempfile


def test_split_runfiles(tmp_path: pathlib.Path) -> None:
    classification = tmp_path / "files"
    classification.write_text(
        "pip external/wheel/site-packages/pkg.py\ninterpreter external/python/bin/python3\n"
    )
    mtree = tmp_path / "input.mtree"
    mtree.write_text(
        "#mtree\n"
        "pkg/app type=file content=out/app\n"
        "pkg/app.runfiles/_main/pkg/app.py type=file content=pkg/app.py\n"
        "pkg/app.runfiles/wheel/site-packages/pkg.py type=file content=external/wheel/site-packages/pkg.py\n"
        "pkg/app.runfiles/python/bin/python3 type=file content=external/python/bin/python3\n"
        "pkg/app.runfiles/_main/pkg/_app.venv/bin/python3 type=link link=../../../../python/bin/python3\n"
        "pkg/app.runfiles/_main/pkg/with\\040space type=file content=pkg/with\\040space\n"
    )
    source = tmp_path / "source.mtree"
    interpreter = tmp_path / "interpreter.mtree"
    subprocess.run(
        [
            os.environ["GAWK"],
            "-v",
            f"classification={classification}",
            "-v",
            "prefix=pkg/app",
            "-v",
            f"source={source}",
            "-v",
            f"interpreter={interpreter}",
            "-f",
            os.environ["SPLIT_AWK"],
            str(mtree),
        ],
        check=True,
    )
    rows = source.read_text()
    assert "./app type=file" in rows
    assert "./app.runfiles/_main/pkg/app.py" in rows
    assert "type=link link=../../../../python/bin/python3" in rows
    assert "with\\040space" in rows
    assert "content=external/" not in rows
    assert (
        interpreter.read_text()
        == "#mtree\n./app.runfiles/python/bin/python3 type=file content=external/python/bin/python3\n"
    )


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as directory:
        test_split_runfiles(pathlib.Path(directory))
