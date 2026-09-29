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
bazel test //...
(cd examples && bazel test //...)
(cd e2e/smoke && bazel test //...)
```

The root contains focused unit and analysis tests. The examples module builds
real package and image archives; the smoke module exercises external-repository
inference with a small APT fixture. Behavioral tests must accompany rule changes.

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
