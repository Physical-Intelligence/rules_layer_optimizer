"""Preserve relative virtualenv links in mtree specs without dereferencing them."""

import os
import pathlib
import re
import sys


def preserve_symlinks(source: pathlib.Path, output: pathlib.Path) -> None:
    with (
        source.open(encoding="utf-8") as src,
        output.open("w", encoding="utf-8") as dst,
    ):
        for line in src:
            fields = line.rstrip("\n").split(" ")
            entry = _decode(fields[0])
            content = next(
                (field[8:] for field in fields if field.startswith("content=")), None
            )
            if (
                "type=file" in fields
                and content is not None
                and re.search(r"/[^/]*(?:[.]venv|_venv)/", entry)
                and "/_wheels/" not in entry
                and os.path.islink(_decode(content))
            ):
                link = os.readlink(_decode(content))
                if not os.path.isabs(link):
                    fields = [
                        "type=link" if field == "type=file" else field
                        for field in fields
                        if not field.startswith(("content=", "nlink="))
                    ]
                    fields.append("link=" + _encode(link))
            dst.write(" ".join(fields) + "\n")


def _decode(value: str) -> str:
    return re.sub(r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), value)


def _encode(value: str) -> str:
    return "".join(
        f"\\{ord(char):03o}" if char in " \\#\t\n\r" else char for char in value
    )


if __name__ == "__main__":
    preserve_symlinks(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
