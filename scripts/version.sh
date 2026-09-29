#!/bin/bash
# Derives the app version from git and prints shell assignments:
#   VERSION      CFBundleShortVersionString, e.g. 0.3.0 (from the nearest v* tag)
#   BUILD        CFBundleVersion, the commit count on HEAD
#   DESCRIPTION  what the About box and `legible --version` show,
#                e.g. "0.3.0 (142, a1b2c3d)" or "0.3.0+2 (144, a1b2c3d-dirty)"
# Never hand-edit versions: tag with `make release VERSION=x.y.z`.
set -euo pipefail
cd "$(dirname "$0")/.."

describe="$(git describe --tags --match 'v[0-9]*' --dirty --always 2>/dev/null || echo "")"
count="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
sha="$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")"

dirty=""
if [[ "$describe" == *-dirty ]] || ! git diff --quiet HEAD 2>/dev/null; then
  dirty="-dirty"
fi

version="0.0.0"
ahead=""
if [[ "$describe" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-([0-9]+)-g[0-9a-f]+)?(-dirty)?$ ]]; then
  version="${BASH_REMATCH[1]}"
  ahead="${BASH_REMATCH[3]}"
fi

description="$version"
[ -n "$ahead" ] && description="$description+$ahead"
description="$description ($count, $sha$dirty)"

printf 'VERSION=%q\nBUILD=%q\nDESCRIPTION=%q\n' "$version" "$count" "$description"
