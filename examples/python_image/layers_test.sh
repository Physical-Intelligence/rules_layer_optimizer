#!/usr/bin/env bash
set -euo pipefail
tar -tzf "$1" > "$TEST_TMPDIR/source_entries"
grep -q 'app.runfiles/_main/python_image/app.py' "$TEST_TMPDIR/source_entries"
if grep -Eq '/site-packages/(colorama/|google_crc32c/|google_crc32c.libs/|backports/)' "$TEST_TMPDIR/source_entries"; then
    echo 'Wheel files leaked into the source layer' >&2
    exit 1
fi
grep -qx 'COLORAMA_AVAILABLE=1' "$2"
grep -q '"size_hint_bytes": 25335' "$3"
