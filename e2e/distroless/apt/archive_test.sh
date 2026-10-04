#!/usr/bin/env bash
set -euo pipefail
tar -tzf "$1" | grep -q 'bash/payload'
