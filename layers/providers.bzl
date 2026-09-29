"""Public layers building blocks."""

load("//layers/private:layer_groups.bzl", _LayerTarsInfo = "LayerTarsInfo", _SizeHintInfo = "SizeHintInfo", _merge_size_hints = "merge_size_hints")

LayerTarsInfo = _LayerTarsInfo
SizeHintInfo = _SizeHintInfo
merge_size_hints = _merge_size_hints
