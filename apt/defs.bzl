"""Public apt building blocks."""

load("//apt/private:inferred_apt_deps.bzl", _apt_inference = "apt_inference", _inferred_apt_deps_rule = "inferred_apt_deps_rule")

apt_inference = _apt_inference
inferred_apt_deps = _inferred_apt_deps_rule
