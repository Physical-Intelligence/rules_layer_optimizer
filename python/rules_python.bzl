"""Layers for rules_python py_binary targets. Inference lives in :inference.bzl."""

load("//python/private:rules_python_layers.bzl", _pip_layer_reducer = "pip_layer_reducer", _py_image_layer = "py_image_layer")

pip_layer_reducer = _pip_layer_reducer
py_image_layer = _py_image_layer
