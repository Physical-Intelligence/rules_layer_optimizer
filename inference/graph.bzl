"""Extension points for packages that attach dependency identities.

`apt` and `python` use these to reuse inference matching and to build rules
that see their own dependency aspects. Image authors should load
`inference:defs.bzl` instead.
"""

load("//inference/private:dependency_inference.bzl", _dependency_graph_aspect = "dependency_graph_aspect", _dependency_identities = "dependency_identities", _inference_matches = "inference_matches", _validate_inference_triggers = "validate_inference_triggers")
load("//inference/private:inferred_env.bzl", _env_inference = "env_inference", _make_env_file = "make_env_file")
load("//inference/private:inferred_layers.bzl", _layer_inference = "layer_inference", _make_inferred_layers = "make_inferred_layers")

dependency_graph_aspect = _dependency_graph_aspect
dependency_identities = _dependency_identities
inference_matches = _inference_matches
validate_inference_triggers = _validate_inference_triggers
env_inference = _env_inference
make_env_file = _make_env_file
layer_inference = _layer_inference
make_inferred_layers = _make_inferred_layers
