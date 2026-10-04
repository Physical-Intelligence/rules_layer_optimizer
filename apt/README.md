# APT layers

`apt:defs.bzl` exports `apt_inference` and `inferred_apt_deps`.
`apt_inference` maps exact dependency labels to `packages` and optional extra
`tars`. Consumers select distributions and package repositories themselves.
Use `python:inference.bzl` for the variants that match logical pip packages.

`inferred_apt_deps` accepts `layer_inference_bundle` targets. It combines matched
mappings with explicit `base_packages` and `packages`. Outputs carry LayerTarsInfo
plus SizeHintInfo for primary package tars. Transitive package tars are retained
and may remain unsized. Duplicate
files are removed and conflicting hints fail analysis.

The adapter identifies a package's primary tar through its public `:data`
dependency. It obtains hints from configured v2 lockfiles and canonical package
labels; renamed Bzlmod repository imports are supported. Multi-architecture
locks conservatively use the maximum compressed package size.

Size parsing requires v2 locks (`dependency_sets` and object-valued `packages`).
The pinned rules_distroless 0.9.4 supplies flattening; choose a resolver that
generates v2 locks or supply an existing compatible lock. Tests use synthetic
package repositories rather than live resolution.

See [configuration](../docs/configuration.md) for module setup. The
[distroless contract](../e2e/distroless/README.md) verifies the adapter contract without a
production APT universe. Base packages, compatibility shims, dpkg status policy,
and distribution selection are deliberately consumer-owned.

## API reference

`apt_inference(name, packages = [], tars = [], for_deps = [], for_keys = [], **kwargs)`
registers a mapping and a private `<name>_for_deps_test` that validates trigger labels.
`packages` receive APT size hints; `tars` are caller-provided additional archives.
The Python variant derives `for_keys` itself from the configured hub.

`inferred_apt_deps(name, deps = [], inferences = [], base_packages = [], packages = [], **kwargs)`
takes `layer_inference_bundle` targets in `inferences`. It collects base packages, matching mappings, then explicit packages in that order.
It exposes `DefaultInfo`, `LayerTarsInfo`, and `SizeHintInfo`.
Both APIs accept ordinary Bazel attributes such as `visibility` and `tags`.
