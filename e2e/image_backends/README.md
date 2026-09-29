# Image backends

Builds the same optimized tars with rules_oci and rules_img, for both Python
adapters, on top of a pinned Ubuntu base. The equivalence test compares layer
digests and the inferred environment. The image tests load each image into
Docker and run it.

`e2e/minimum` rebuilds these packages at the oldest supported backend versions.
