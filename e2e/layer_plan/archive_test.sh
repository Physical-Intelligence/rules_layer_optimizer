#!/usr/bin/env bash
set -euo pipefail
tar -tzf "$1" > "$TEST_TMPDIR/entries"
grep -q 'payload.txt' "$TEST_TMPDIR/entries"
grep -q 'empty' "$TEST_TMPDIR/entries"
grep -q '"disposition": "flattened"' "$2"
grep -q '"missing_size_hint"' "$2"
