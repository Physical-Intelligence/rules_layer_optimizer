"""Layers for aspect_rules_py py_binary targets."""

load("//python:defs.bzl", _pip_layer_reducer = "pip_layer_reducer", _py_image_layer = "py_image_layer", _source_dep_bucket = "source_dep_bucket", _source_dep_match = "source_dep_match")

pip_layer_reducer = _pip_layer_reducer
py_image_layer = _py_image_layer
source_dep_bucket = _source_dep_bucket
source_dep_match = _source_dep_match
