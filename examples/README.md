# Examples

This separate Bazel module consumes the library through `local_path_override`.
Its dependencies and policies belong to the consumer, not the library module.

The example directories are reserved for the extraction work:

- `basic_layers/`: group tar layers and apply a shared size budget.
- `python_image/`: compose Python and APT layers into an image with a
  consumer-owned assembly macro.
- `shared_dependencies/`: demonstrate identical package layers across binaries.

No working image examples are included yet. The current `library_readme` target
only checks external-module resolution.
