# Compatibility

The ruleset is validated with Bazel 9.2.0 on Ubuntu 24.04 x86-64.
The legacy minimum-version fixture uses Bazel 8.7.0 because rules_oci 1.1.0
uses an upstream rule argument removed in Bazel 9. Current-version consumers
use Bazel 9.2.0. Other execution platforms are not yet claimed as supported.

## Supported versions

| Dependency | Minimum supported | Current test endpoint |
| --- | --- | --- |
| `rules_oci` | **1.1.0** | 2.2.6 |
| `rules_img` | **0.3.12** | 0.3.22 |
| `rules_python` | **1.9.0** | 1.9.0 |
| `aspect_rules_py` | **2.0.0-alpha.4** | 2.0.0-alpha.4 |

The current [image backend checks](../e2e/image_backends/README.md) and the
[minimum module](../e2e/minimum/README.md) run all four Python/image-backend
combinations in Docker. The minimum module pins exact
versions with root-only overrides and verifies the resolved module graph. This
prevents transitive version upgrades from invalidating minimum-version coverage.
These are supported floors, not a claim that every future release has been tested.

## Declaring minimums

For direct dependencies, the versions in [MODULE.bazel](../MODULE.bazel) are the
supported lower bounds. Bzlmod's
[Minimal Version Selection](https://bazel.build/versions/9.2.0/external/module#version-selection)
selects the highest version requested anywhere in the dependency graph. It can
upgrade those bounds when another dependency requires more, but does not normally
select an older version. No redundant runtime version checker is needed.

The image backends are optional consumer dependencies: the library produces tars
and does not load either backend. Their supported floors are declared in the table
above and exercised by the minimum consumer. Consumers declare the backend they
use, for example `bazel_dep(name = "rules_oci", version = "1.1.0")`. Adding both
as production dependencies here would unnecessarily impose them on every consumer.

Root-module overrides can deliberately bypass normal version selection. We do
not prohibit that escape hatch with a custom hard failure, but versions below the
supported floors are outside the tested contract.
