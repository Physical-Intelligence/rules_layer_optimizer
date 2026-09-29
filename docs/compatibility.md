# Compatibility

The extracted implementation is validated with Bazel 8.7.0 on Linux x86-64.
Other Bazel versions and execution platforms are not yet claimed as supported.
The examples use only public dependencies, without monopi patches or overrides.

- `aspect_rules_py` 2.0.0-alpha.4: Python layers use its private `PyWheelsInfo`
  provider and generated wheel repository layout. This compatibility surface is
  isolated in `python/private/aspect_rules_py.bzl`; upgrades need integration tests.
- `rules_distroless` 0.9.4: supplies tar flattening. APT size parsing requires the
  newer **v2 lock schema** (`dependency_sets` and object-valued `packages`). The
  tested flattening release and the v2 APT resolver are separate compatibility
  boundaries. This repo does not claim that 0.9.4 generates v2 locks; users need
  a compatible resolver or an existing v2 lock. APT adapter tests use a synthetic
  package repository matching the public `:data` contract, not live APT resolution.
- `aspect_bazel_lib` 2.22.0 supplies tar/mtree actions; gawk is a declared dependency.
- The Python image example uses `rules_oci` 2.2.6. Output tars can be composed by
  other OCI rule sets; rules_img integration has not been tested in this extraction.

Python layers use `/app` and `/app.runfiles` as their shared image paths. The
caller supplies the interpreter tar and execution toolchain. No interpreter
pruning, Ubuntu base policy, registry destinations, or deployment integration
is included. The example chooses a digest-pinned Ubuntu base and an x86-64
interpreter explicitly.

The optimizer's layer budget counts the layers it emits. When extending an
existing image, callers must subtract the base image's layers from their desired
runtime limit. Size hints estimate input package sizes; they are not measured
output archive sizes. Small packages share an overflow layer, so changing one
can rebuild that group. No runtime-independent maximum layer count is assumed.
