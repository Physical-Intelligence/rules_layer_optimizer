"""Public python building blocks."""

load("//python/private:py_image_layer.bzl", _pip_layer_reducer = "pip_layer_reducer", _py_image_layer = "py_image_layer")
load("//python/private:source_dep_buckets.bzl", _source_dep_bucket = "source_dep_bucket", _source_dep_match = "source_dep_match")

py_image_layer = _py_image_layer
pip_layer_reducer = _pip_layer_reducer
source_dep_bucket = _source_dep_bucket
source_dep_match = _source_dep_match
