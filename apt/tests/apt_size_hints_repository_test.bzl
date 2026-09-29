"""Tests for APT size hint repository rendering helpers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//apt/private:apt_size_hints.bzl",
    "parse_apt_lock_size_hints",
    "render_apt_size_hints_bzl",
)

def _parse_apt_lock_test_impl(ctx):
    env = unittest.begin(ctx)

    size_hints = parse_apt_lock_size_hints("""
{
  "dependency_sets": {
    "noble": {
      "sets": {
        "amd64": {
          "/noble/bash:amd64": "1.0",
          "/noble/libc6:amd64": "2.0"
        },
        "arm64": {
          "/noble/bash:arm64": "1.1"
        }
      }
    }
  },
  "packages": {
    "/noble/bash:amd64=1.0": {"name": "bash", "size": 100},
    "/noble/bash:arm64=1.1": {"name": "bash", "size": 150},
    "/noble/libc6:amd64=2.0": {"name": "libc6", "size": 200},
    "/noble/unselected:amd64=3.0": {"name": "unselected", "size": 300}
  }
}
    """, "noble", "rules_distroless+apt+ubuntu_24")

    asserts.equals(
        env,
        {
            "@@rules_distroless+apt+ubuntu_24//bash:bash": 150,
            "@@rules_distroless+apt+ubuntu_24//libc6:libc6": 200,
        },
        size_hints,
    )
    return unittest.end(env)

parse_apt_lock_test = unittest.make(_parse_apt_lock_test_impl)

def _render_apt_size_hints_test_impl(ctx):
    env = unittest.begin(ctx)

    rendered = render_apt_size_hints_bzl({
        "@@rules_distroless+apt+noble//libc6:libc6": 200,
        "@@rules_distroless+apt+jammy//bash:bash": 100,
    })

    expected = '''APT_PACKAGE_SIZE_HINTS = {
    "@@rules_distroless+apt+jammy//bash:bash": 100,
    "@@rules_distroless+apt+noble//libc6:libc6": 200,
}
'''
    asserts.equals(env, expected, rendered)
    return unittest.end(env)

render_apt_size_hints_test = unittest.make(_render_apt_size_hints_test_impl)

def apt_size_hints_repository_test_suite(name):
    """Instantiates the APT size hint repository helper tests."""
    parse_apt_lock_test(
        name = name + "_parse_apt_lock_test",
    )
    render_apt_size_hints_test(
        name = name + "_render_apt_size_hints_test",
    )

    native.test_suite(
        name = name,
        tests = [
            ":" + name + "_parse_apt_lock_test",
            ":" + name + "_render_apt_size_hints_test",
        ],
    )
