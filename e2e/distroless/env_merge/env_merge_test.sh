#!/usr/bin/env bash
set -euo pipefail
grep -qx 'PATH=/bin:/tools:/extra' "$1"
grep -qx 'MODE=test' "$1"
