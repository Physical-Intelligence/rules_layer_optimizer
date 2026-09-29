"""Reusable aspect_rules_py package, interpreter, and source layers."""

load("//python/private:py_image_layer.bzl", _pip_layer_reducer = "pip_layer_reducer", _py_image_layer = "py_image_layer")

pip_layer_reducer = _pip_layer_reducer
py_image_layer = _py_image_layer
