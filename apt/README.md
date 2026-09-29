# APT layers

`apt:defs.bzl` exports `apt_inference` and `inferred_apt_deps`.
`apt_inference` maps exact dependency labels to `packages` and optional extra
`tars`. Consumers select distributions and package repositories themselves.
Use `python:inference.bzl` for the variants that match logical pip packages.

`inferred_apt_deps` combines matched mappings with explicit `base_packages` and
`packages`. Outputs carry LayerTarsInfo plus SizeHintInfo for primary package
tars. Transitive package tars are retained and may remain unsized. Duplicate
files are removed and conflicting hints fail analysis.

The adapter identifies a package's primary tar through its public `:data`
dependency. It obtains hints from configured v2 lockfiles and canonical package
labels; renamed Bzlmod repository imports are supported. Multi-architecture
locks conservatively use the maximum compressed package size.

See [configuration](../docs/configuration.md) and
[compatibility](../docs/compatibility.md) for the v2-lock requirement. The
[smoke module](../e2e/smoke/README.md) verifies the adapter contract without a
production APT universe. Base packages, compatibility shims, dpkg status policy,
and distribution selection are deliberately consumer-owned.
