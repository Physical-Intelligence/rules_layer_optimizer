"""Tests for configurable source-dependency buckets."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//python/private:source_dep_buckets.bzl", "source_dep_bucket", "source_dep_bucket_matches_file", "source_dep_match")

def _source_dep_buckets_test_impl(ctx):
    env = unittest.begin(ctx)

    cases = [
        (source_dep_match("path_contains", value = "/assets/"), _file("pkg/assets/model.bin"), _file("pkg/models/model.bin")),
        (source_dep_match("path_suffix", value = "/weights.bin"), _file("pkg/weights.bin"), _file("pkg/weights.txt")),
        (source_dep_match("segment_suffix", value = ".runfiles"), _file("pkg/tool.runfiles/data"), _file("pkg/tool/data")),
        (source_dep_match("exact_path", values = ["pkg/tool"]), _file("_main/pkg/tool"), _file("_main/pkg/other")),
        (source_dep_match("generated_exact_path", values = ["pkg/tool"]), _file("_main/pkg/tool", "bazel-out/bin/pkg/tool"), _file("_main/pkg/tool", "pkg/tool")),
        (source_dep_match("repository_rule", value = "generated_repo"), _file("../rules+generated_repo+data/pkg/file"), _file("../other_repo/pkg/file")),
        (source_dep_match("basename_contains_with_suffixes", value = "tokenizer", values = [".json", ".model"]), _file("pkg/my_tokenizer.model"), _file("pkg/my_tokenizer.txt")),
    ]
    for matcher, matching_file, nonmatching_file in cases:
        bucket = source_dep_bucket(name = matcher.kind, patterns = [matcher.kind], matchers = [matcher])
        asserts.true(env, source_dep_bucket_matches_file(bucket, matching_file), matcher.kind)
        asserts.false(env, source_dep_bucket_matches_file(bucket, nonmatching_file), matcher.kind)

    first_party = source_dep_bucket(
        name = "first_party",
        patterns = ["assets"],
        matchers = [source_dep_match("path_contains", value = "/assets/")],
        first_party_only = True,
    )
    asserts.true(env, source_dep_bucket_matches_file(first_party, _file("pkg/assets/model.bin")))
    asserts.false(env, source_dep_bucket_matches_file(first_party, _file("../repo/pkg/assets/model.bin")))

    return unittest.end(env)

source_dep_buckets_test = unittest.make(_source_dep_buckets_test_impl)

def source_dep_buckets_test_suite(name):
    source_dep_buckets_test(name = name)

def _file(short_path, path = None):
    return struct(path = path or short_path, short_path = short_path)
