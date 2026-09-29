#!/usr/bin/env bash
set -euo pipefail

output=$(mktemp -d)
trap 'rm -rf "$output"' EXIT
bazel run //tools:release -- \
  --output "$output" --repository "$GITHUB_REPOSITORY" --tag "$1" --verify >&2
mkdir -p dist
cp "$output"/*.tar.gz "$output/source.json" "$output/installation.MODULE.bazel" dist/
printf '```starlark\n'
cat "$output/installation.MODULE.bazel"
printf '```\n'
