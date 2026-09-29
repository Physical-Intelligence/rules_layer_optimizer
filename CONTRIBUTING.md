# Contributing

This repository is being prepared privately. Do not make it public, publish a
release, or submit it to the Bazel Central Registry without Jimmy's explicit
approval.

## Local checks

Use Bazelisk to select the version in `.bazelversion`. Install `pre-commit`, then
install both hook stages:

```sh
pre-commit install --hook-type pre-commit --hook-type pre-push
pre-commit run --all-files
bazel build //...
(cd examples && bazel build //...)
(cd e2e/smoke && bazel build //...)
```

The scaffold has no rule implementations or behavioral tests yet. The external
modules check basic module resolution through `local_path_override`; behavioral
and analysis tests must accompany each extracted rule. Run them with
`bazel test //...` once they are present.

Use Graphite for branches and draft PRs. Keep PRs as drafts without reviewers
until the author explicitly chooses to request review.

## API boundaries

Public `.bzl` entrypoints belong at the capability package root. Implementations
and upstream compatibility adapters belong in its `private/` package. Keep
focused tests in the adjacent `tests/` package. Document supported symbols when
introducing them; do not expose empty or placeholder APIs.

Keep consumer-owned image assembly in `examples/`. Do not introduce a supported
`py_image` API. Formatting, documentation generators, and test-only dependencies
should be marked `dev_dependency = True` where applicable.
