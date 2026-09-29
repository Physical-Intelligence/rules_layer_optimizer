"""Check that image helpers preserve consumer tag policy."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

def _tags_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.true(env, bool(ctx.attr.observed))
    for name, tags in ctx.attr.observed.items():
        asserts.equals(env, ctx.attr.expected, tags, name)
    return unittest.end(env)

_tags_test = unittest.make(_tags_test_impl, attrs = {
    "observed": attr.string_list_dict(),
    "expected": attr.string_list(),
})

def tags_test(name, prefix, expected):
    """Snapshot the generated targets' tags after invoking py_image_layer."""
    _tags_test(
        name = name,
        expected = sorted(expected),
        observed = {
            name: sorted(target.get("tags", []))
            for name, target in native.existing_rules().items()
            if name.startswith(prefix) or name.startswith("_" + prefix)
        },
    )
