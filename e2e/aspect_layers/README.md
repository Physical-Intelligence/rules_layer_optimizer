# aspect_rules_py layer checks

Each package checks one behavior of the aspect_rules_py adapter:

- `wheel_reuse`: two consumers receive the same wheel archive and size.
- `package_inference`: a pip package selects the same tar through layer and apt inference.
- `source_layers`: source partitions, exclusions, and wheel files staying out of the source layer.
- `caller_tags`: generated targets keep the caller's tags.
