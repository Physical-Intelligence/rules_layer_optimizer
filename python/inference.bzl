"""Python-aware layer, APT, and environment inference.

Use these adapters to match configured pip-hub labels through a Python graph.
"""

load("//python/private:inference.bzl", _apt_inference = "apt_inference", _env_file = "env_file", _env_inference = "env_inference", _inferred_apt_deps = "inferred_apt_deps", _inferred_layers = "inferred_layers", _layer_inference = "layer_inference")

layer_inference = _layer_inference
inferred_layers = _inferred_layers
apt_inference = _apt_inference
inferred_apt_deps = _inferred_apt_deps
env_inference = _env_inference
env_file = _env_file
