# Contributing

## Local checks

Use Bazelisk to select the version in `.bazelversion`. Install `pre-commit`, then
install both hook stages:

```sh
pre-commit install --hook-type pre-commit --hook-type pre-push
pre-commit run --all-files
bazel test //...
(cd examples/py_image_with_rules_oci_and_aspect_rules_py && bazel test //...)
(cd examples/py_image_with_rules_img_and_rules_python && bazel test //...)
(cd e2e/layer_plan && bazel test //...)
(cd e2e/aspect_layers && bazel test //...)
(cd e2e/rules_python_layers && bazel test //...)
(cd e2e/image_backends && bazel test //...)
(cd e2e/minimum && bazel test //...)
(cd e2e/distroless && bazel test //...)
(cd e2e/inference && bazel test //...)
(cd e2e/rules_python && bazel test //...)
```

The root contains focused unit and analysis tests. The example modules build
runnable images. Each package under `e2e/` checks one behavior. Behavioral
tests must accompany rule changes.
After committing changes, rehearse archive installation with
`bazel run //tools:release -- --output /tmp/rules_layer_optimizer_release --verify`.
This packages committed HEAD, not working-tree edits.

CI discovers every tracked
`MODULE.bazel` and tests each module independently; `.bazelignore` only prevents
one module's wildcard expansion from crossing into another module.
The required `all-tests-passed` check covers the entire dynamic matrix and
fails if any prerequisite fails, is cancelled, or is unexpectedly skipped.

Each example with an optimizer checks its complete generated plan against
`optimization_plan.json`. Refresh it with `bazel run :write_optimization_plan`
in that example's package, then review the full diff before committing.

## Releases

Maintainers update `MODULE.bazel` and the README installation version, then
push a matching
`vX.Y.Z` tag to trigger the [Release workflow](.github/workflows/release.yaml).
GitHub tag protection limits release tags to maintainers and administrators.
The shared Bazel workflow verifies the archive and publishes the GitHub release
with provenance attestations. See [.bcr](.bcr/README.md) for release details and
registry metadata.
