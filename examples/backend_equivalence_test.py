"""Assert both image backends preserve layer order and inferred runtime config."""

import json
import pathlib
import sys
from typing import Any


def test_backend_equivalence(oci: pathlib.Path, img: pathlib.Path) -> None:
    def read_blob(layout: pathlib.Path, digest: str) -> dict[str, Any]:
        algorithm, checksum = digest.split(":", 1)
        return json.loads((layout / "blobs" / algorithm / checksum).read_text())

    manifests = []
    configs = []
    for layout in (oci, img):
        index = json.loads((layout / "index.json").read_text())
        manifest = read_blob(layout, index["manifests"][0]["digest"])
        manifests.append(manifest)
        configs.append(read_blob(layout, manifest["config"]["digest"]))
    assert [layer["digest"] for layer in manifests[0]["layers"]] == [
        layer["digest"] for layer in manifests[1]["layers"]
    ]
    assert len(manifests[0]["layers"]) <= 9  # Eight optimized layers plus the base.
    assert configs[0]["rootfs"]["diff_ids"] == configs[1]["rootfs"]["diff_ids"]
    for config in configs:
        assert config["config"]["Entrypoint"] == ["/app"]
        assert "COLORAMA_AVAILABLE=1" in config["config"]["Env"]


if __name__ == "__main__":
    test_backend_equivalence(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
