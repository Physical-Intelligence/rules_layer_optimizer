"""Configuration helpers for stable source-dependency OCI layers."""

def source_dep_match(kind, value = "", values = []):
    """Defines one file matcher for a source-dependency bucket.

    Args:
        kind: Matcher kind, such as path_suffix or exact_path.
        value: Single value for the selected matcher.
        values: Multiple values or suffixes for the selected matcher.

    Returns:
        An immutable matcher specification.
    """
    if kind not in _MATCHERS:
        fail("unsupported source dependency matcher kind '{}'".format(kind))
    if kind == "basename_contains_with_suffixes":
        if not value or not values:
            fail("source dependency matcher '{}' requires both value and values".format(kind))
    elif bool(value) == bool(values):
        fail("source dependency matcher '{}' requires exactly one of value or values".format(kind))
    return struct(kind = kind, value = value, values = tuple(values))

def source_dep_bucket(
        name,
        patterns,
        matchers = [],
        include_if_executable = False,
        first_party_only = False,
        exclude_pyo3 = False):
    """Defines one optional source-dependency layer and its presence test.

    Args:
        name: Name of the generated target or test suite.
        patterns: Mtree path regular expressions assigned to this bucket.
        matchers: Artifact matchers used to decide whether the bucket is present.
        include_if_executable: Include the bucket when the binary has an executable.
        first_party_only: Restrict artifact matching to the main repository.
        exclude_pyo3: Exclude separately layered PyO3 artifacts.

    Returns:
        An immutable source bucket specification.
    """
    if not name or not patterns:
        fail("source dependency buckets require a name and at least one mtree pattern")
    if not matchers and not include_if_executable:
        fail("source dependency bucket '{}' requires a presence condition".format(name))
    return struct(
        exclude_pyo3 = exclude_pyo3,
        first_party_only = first_party_only,
        include_if_executable = include_if_executable,
        matchers = tuple(matchers),
        name = name,
        patterns = tuple(patterns),
    )

def source_dep_bucket_matches_file(bucket, file):
    """Returns whether a runfile selects a configured source-dependency bucket.

    Args:
        bucket: Bucket created by source_dep_bucket.
        file: Artifact to match against the bucket.

    Returns:
        Whether the artifact satisfies the bucket policy.
    """
    path = file.short_path
    if bucket.first_party_only and not _is_first_party_runfile_artifact(path):
        return False
    return any([_matcher_matches_file(matcher, file) for matcher in bucket.matchers])

def _matcher_matches_file(matcher, file):
    return _MATCHERS[matcher.kind](matcher, file)

def _basename_contains_with_suffixes(matcher, file):
    basename = file.short_path.rpartition("/")[2]
    return matcher.value in basename and any([basename.endswith(suffix) for suffix in matcher.values])

def _exact_path(matcher, file):
    return _main_relative_path(file.short_path) in matcher.values

def _generated_exact_path(matcher, file):
    return file.path.startswith("bazel-out/") and _exact_path(matcher, file)

def _path_contains(matcher, file):
    return matcher.value in file.short_path

def _path_suffix(matcher, file):
    return file.short_path.endswith(matcher.value)

def _repository_rule(matcher, file):
    return _repository_rule_repo_in_path(file.short_path, matcher.value)

def _segment_suffix(matcher, file):
    return any([segment.endswith(matcher.value) for segment in file.short_path.split("/")])

def _repository_rule_repo_in_path(path, rule_name):
    return "+{}+".format(rule_name) in path or "~{}~".format(rule_name) in path

def _is_first_party_runfile_artifact(path):
    return not path.startswith("../") and not path.startswith("external/") and "/external/" not in path

def _main_relative_path(path):
    if path.startswith("_main/"):
        return path[6:]
    return path

_MATCHERS = {
    "basename_contains_with_suffixes": _basename_contains_with_suffixes,
    "exact_path": _exact_path,
    "generated_exact_path": _generated_exact_path,
    "path_contains": _path_contains,
    "path_suffix": _path_suffix,
    "repository_rule": _repository_rule,
    "segment_suffix": _segment_suffix,
}
