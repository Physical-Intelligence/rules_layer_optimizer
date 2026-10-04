# rules_python layer checks

Each package checks one behavior of the rules_python adapter:

- `reuse`: two binaries receive the same wheel archives and sizes.
- `contents`: wheel archives contain importable code, and the source archive does not.
- `caller_tags`: generated targets keep the caller's tags.
