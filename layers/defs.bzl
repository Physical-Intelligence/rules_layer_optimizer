"""Public layers building blocks."""

load("//layers/private:layer_groups.bzl", _layer_group = "layer_group")
load("//layers/private:optimize_layers.bzl", _MAX_DOCKER_LAYERS = "MAX_DOCKER_LAYERS", _optimized_layers_plan = "optimized_layers_plan")

layer_group = _layer_group
MAX_DOCKER_LAYERS = _MAX_DOCKER_LAYERS
optimized_layers_plan = _optimized_layers_plan
