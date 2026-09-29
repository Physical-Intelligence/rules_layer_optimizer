"""Public inference building blocks."""

load("//inference/private:dependency_inference.bzl", _DependencyGraphInfo = "DependencyGraphInfo", _DependencyKeyInfo = "DependencyKeyInfo")
load("//inference/private:inferred_layers.bzl", _LayerInferenceBundleInfo = "LayerInferenceBundleInfo", _LayerInferenceInfo = "LayerInferenceInfo")

DependencyGraphInfo = _DependencyGraphInfo
DependencyKeyInfo = _DependencyKeyInfo
LayerInferenceInfo = _LayerInferenceInfo
LayerInferenceBundleInfo = _LayerInferenceBundleInfo
