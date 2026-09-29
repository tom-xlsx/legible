#!/bin/bash
# Fetches the pinned JS/CSS dependencies from npm and copies the browser
# builds into Resources/web/vendor/. Run once (or when bumping a version);
# the results are committed, so the app never touches the network.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Resources/web/vendor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# name@version  →  file(s) to copy (relative to the unpacked package/ dir)
PKGS=(
  "markdown-it@14.1.0            dist/markdown-it.min.js"
  "markdown-it-footnote@4.0.0    dist/markdown-it-footnote.min.js"
  "markdown-it-task-lists@2.1.1  dist/markdown-it-task-lists.min.js"
  "dompurify@3.2.6               dist/purify.min.js"
  "@highlightjs/cdn-assets@11.11.1 highlight.min.js languages"
)

mkdir -p "$VENDOR"
: > "$VENDOR/VERSIONS"

cd "$WORK"
for entry in "${PKGS[@]}"; do
  read -r spec files <<<"$entry"
  echo "→ $spec"
  tgz="$(npm pack --silent "$spec")"
  dir="$WORK/$(basename "$tgz" .tgz)"
  mkdir -p "$dir" && tar -xzf "$tgz" -C "$dir"
  for f in $files; do
    src="$dir/package/$f"
    if [ -d "$src" ]; then
      rm -rf "$VENDOR/$(basename "$f")"
      cp -R "$src" "$VENDOR/$(basename "$f")"
    else
      cp "$src" "$VENDOR/$(basename "$f")"
    fi
  done
  echo "$spec" >> "$VENDOR/VERSIONS"
done

# The common build already bundles the usual languages; keep only extras it lacks.
KEEP="dockerfile nginx http"
mkdir -p "$VENDOR/languages.keep"
for lang in $KEEP; do
  [ -f "$VENDOR/languages/$lang.min.js" ] && mv "$VENDOR/languages/$lang.min.js" "$VENDOR/languages.keep/"
done
rm -rf "$VENDOR/languages"
mv "$VENDOR/languages.keep" "$VENDOR/languages"

echo "Vendored:"; cat "$VENDOR/VERSIONS"; du -sh "$VENDOR"
