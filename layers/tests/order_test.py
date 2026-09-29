"""Apply ordered fixture layers to check overwrite and deletion semantics."""

import pathlib
import sys
import tarfile


def test_ordered_overwrites_and_whiteouts(layers: list[str]) -> None:
    files: dict[str, bytes] = {}
    for layer in layers:
        with tarfile.open(layer) as archive:
            members = archive.getmembers()
            # OCI whiteouts affect lower layers, not other entries in this layer.
            for member in members:
                path = pathlib.PurePosixPath(member.name)
                if path.name == ".wh..wh..opq":
                    files = {
                        name: data
                        for name, data in files.items()
                        if not name.startswith(str(path.parent) + "/")
                    }
                elif path.name.startswith(".wh."):
                    files.pop(str(path.with_name(path.name[4:])), None)
            for member in members:
                if member.isfile() and not pathlib.PurePosixPath(
                    member.name
                ).name.startswith(".wh."):
                    content = archive.extractfile(member)
                    assert content is not None
                    files[str(pathlib.PurePosixPath(member.name))] = content.read()
    assert files == {"value": b"new\n", "dir/new": b"new\n"}, files


if __name__ == "__main__":
    test_ordered_overwrites_and_whiteouts(sys.argv[1:])
