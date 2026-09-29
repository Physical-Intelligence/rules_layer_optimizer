# Examples

These are the user-facing image examples. Each one is a separate Bazel module
whose call site is only `name` and a `py_binary`.

- [py_image_with_rules_oci_and_aspect_rules_py](py_image_with_rules_oci_and_aspect_rules_py/app/BUILD.bazel)
  uses rules_oci and aspect_rules_py. The [shared package](py_image_with_rules_oci_and_aspect_rules_py/shared/BUILD.bazel)
  supplies base apt packages, the interpreter, and the inference bundles.
- [py_image_with_rules_img_and_rules_python](py_image_with_rules_img_and_rules_python/app/BUILD.bazel)
  uses rules_img and rules_python. The [shared package](py_image_with_rules_img_and_rules_python/shared/BUILD.bazel)
  supplies base apt packages and the inference bundles.

```sh
(cd py_image_with_rules_oci_and_aspect_rules_py && bazel test //...)
docker run --rm --network none rules-layer-optimizer-py-image:local
(cd py_image_with_rules_img_and_rules_python && bazel test //...)
docker run --rm --network none rules-layer-optimizer-py-image-rules-python:local
```

[py_image.bzl](py_image_with_rules_oci_and_aspect_rules_py/shared/py_image.bzl)
and
[py_image.bzl](py_image_with_rules_img_and_rules_python/shared/py_image.bzl) are
caller-owned wrappers. The ruleset does not export a `py_image` rule. Focused
checks for individual behaviors live under [e2e](../e2e).
