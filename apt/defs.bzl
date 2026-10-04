"""Public apt building blocks."""

load("//apt/private:inferred_apt_deps.bzl", _apt_inference = "apt_inference", _inferred_apt_deps_rule = "inferred_apt_deps_rule", _make_inferred_apt_deps = "make_inferred_apt_deps")

apt_inference = _apt_inference
inferred_apt_deps = _inferred_apt_deps_rule
make_inferred_apt_deps = _make_inferred_apt_deps
