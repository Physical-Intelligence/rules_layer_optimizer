"""Public APT lock size-hint repository rule."""

load("//apt/private:apt_size_hints.bzl", _apt_size_hints_repository = "apt_size_hints_repository")

apt_size_hints_repository = _apt_size_hints_repository
