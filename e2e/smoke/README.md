# External-consumer smoke tests

Run `bazel test //...` here to test the library outside its root module with no
configured pip hub. Public entrypoints exercise graph matching, APT size-hint
propagation, duplicate package removal, environment merging and conflict errors,
and materialized archive contents.

The `debs` repository is a small fixture with the public distroless `:data`
relationship. Its v2 lock supplies deterministic size metadata. This isolates
adapter and Bzlmod repository-mapping behavior; it is not a live APT resolver test.
