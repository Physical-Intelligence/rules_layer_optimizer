"""Check source partitions, first-match precedence, exclusions, and native files."""

import sys
import tarfile


def test_source_layers(paths: list[str]) -> None:
    layers = []
    for path in paths:
        with tarfile.open(path) as archive:
            contents = {}
            for entry in archive.getmembers():
                if "/fixtures/" not in entry.name or not entry.isfile():
                    continue
                file = archive.extractfile(entry)
                assert file is not None
                contents[entry.name.rsplit("/", 1)[-1]] = file.read()
            layers.append(contents)
    assert layers == [
        {"binding.so": b"native payload"},
        {"first.txt": b"first"},
        {"third.txt": b"third"},
        {},
    ]


if __name__ == "__main__":
    test_source_layers(sys.argv[1:])
