"""Order-sensitive tar fixtures must bypass flattening and size sorting."""

load("@aspect_bazel_lib//lib:tar.bzl", "tar")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_python//python:defs.bzl", "py_test")
load("//layers:defs.bzl", "layer_group")
load("//layers:distroless.bzl", "optimized_layers")

def order_test(name):
    """Exercise real output archives with overwrites and both whiteout forms.

    Args:
        name: Name of the regression test.
    """
    for value in ["old", "new"]:
        write_file(name = value + "_payload", out = value + ".txt", content = [value, ""])
    tar(
        name = "lower",
        srcs = [":old_payload"],
        mtree = [
            "value type=file content=$(location :old_payload)",
            "removed type=file content=$(location :old_payload)",
            "dir/old type=file content=$(location :old_payload)",
        ],
    )
    tar(
        name = "upper",
        srcs = [":new_payload"],
        mtree = [
            "value type=file content=$(location :new_payload)",
            ".wh.removed type=file size=0",
            "dir/.wh..wh..opq type=file size=0",
            "dir/new type=file content=$(location :new_payload)",
        ],
    )
    optimized_layers(
        name = "ordered_layers",
        groups = [layer_group(name = "ordered", targets = [":lower", ":upper"])],
        layer_budget = 2,
        size_bytes_threshold = 0,
    )
    py_test(
        name = name,
        srcs = ["order_test.py"],
        main = "order_test.py",
        args = ["$(locations :ordered_layers)"],
        data = [":ordered_layers"],
    )
