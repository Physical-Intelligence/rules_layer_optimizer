"""rules_distroless adapter for APT package layer metadata."""

load("//apt/private:apt_utils.bzl", "apt_package_size_hint")

# buildifier: disable=bzl-visibility
load("//layers/private:layer_groups.bzl", "SizeHintInfo")

def _primary_files_for_package(target, ctx):
    """Extract the primary tar exposed by a rules_distroless package target."""
    for source in getattr(ctx.rule.attr, "srcs", []):
        if source.label.name == "data":
            return source.files.to_list()
    fail("{} does not expose its primary tar through a public :data target".format(target.label))

def _apt_size_hint_aspect_impl(target, ctx):
    size_hint = apt_package_size_hint(target.label)
    return [SizeHintInfo(sizes = {
        file: size_hint
        for file in _primary_files_for_package(target, ctx)
    })]

apt_size_hint_aspect = aspect(
    implementation = _apt_size_hint_aspect_impl,
    provides = [SizeHintInfo],
)
