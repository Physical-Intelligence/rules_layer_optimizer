"""Public inference building blocks."""

load("//inference/private:inferred_env.bzl", _env_file = "env_file", _env_inference = "env_inference", _env_inference_bundle = "env_inference_bundle")
load("//inference/private:inferred_layers.bzl", _inferred_layers = "inferred_layers", _layer_inference = "layer_inference", _layer_inference_bundle = "layer_inference_bundle")

layer_inference = _layer_inference
layer_inference_bundle = _layer_inference_bundle
inferred_layers = _inferred_layers
env_inference = _env_inference
env_inference_bundle = _env_inference_bundle
env_file = _env_file
