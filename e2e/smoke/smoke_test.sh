#!/usr/bin/env bash
set -euo pipefail
tar -tzf "$1" | grep -q 'bash/payload'
grep -qx 'PATH=/bin:/tools:/extra' "$2"
grep -qx 'MODE=test' "$2"
