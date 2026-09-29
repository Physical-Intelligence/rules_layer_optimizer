"""Infer package-triggered environment entries without package size metadata."""

import pathlib
import sys


def test_inferred_environment(path: pathlib.Path) -> None:
    assert path.read_text() == "FLAGS=--first --second\n"


if __name__ == "__main__":
    test_inferred_environment(pathlib.Path(sys.argv[1]))
