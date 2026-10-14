#!/bin/bash
# Publishes the release HEAD is tagged with: builds the zip, pushes, creates the
# GitHub release, then bumps the Homebrew cask in the tap and pushes that too.
#
#   make release VERSION=x.y.z    # tag + install (existing)
#   make publish                  # this script
#
# LEGIBLE_TAP points at the tap checkout (default: ../homebrew-tap).
# --dry-run prints every command instead of running it.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=""
[ "${1:-}" = "--dry-run" ] && DRY="echo + "
run() { if [ -n "$DRY" ]; then echo "+ $*"; else "$@"; fi; }

TAP="${LEGIBLE_TAP:-$PWD/../homebrew-tap}"
TAP_NAME="tom-xlsx/tap"
CASK="$TAP/Casks/legible.rb"

# -- preconditions ---------------------------------------------------------
[ -z "$(git status --porcelain)" ] || { echo "publish: the tree is not clean" >&2; exit 1; }
TAG="$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null)" || { echo "publish: HEAD is not tagged (make release VERSION=x.y.z first)" >&2; exit 1; }
V="${TAG#v}"
[ -f "$CASK" ] || { echo "publish: no cask at $CASK (set LEGIBLE_TAP)" >&2; exit 1; }
[ -z "$(git -C "$TAP" status --porcelain)" ] || { echo "publish: the tap at $TAP is not clean" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "publish: gh is not logged in (gh auth login)" >&2; exit 1; }
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "publish: release $TAG already exists; a replaced zip would break installs, so refusing" >&2; exit 1
fi

# -- build and checksum -----------------------------------------------------
run make dist
ZIP="build/dist/Legible-$V.zip"
[ -n "$DRY" ] || [ -f "$ZIP" ] || { echo "publish: $ZIP was not built" >&2; exit 1; }
SHA="$([ -n "$DRY" ] && echo '<sha256>' || shasum -a 256 "$ZIP" | cut -d' ' -f1)"

# -- GitHub release ---------------------------------------------------------
run git push origin main
run git push origin "$TAG"
run gh release create "$TAG" "$ZIP" --title "Legible $V" --notes-from-tag --verify-tag

# -- tap bump ---------------------------------------------------------------
if [ -n "$DRY" ]; then
  echo "+ sed -i '' version=$V sha256=$SHA $CASK"
else
  sed -i '' -e "s/^  version \".*\"/  version \"$V\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
  grep -q "version \"$V\"" "$CASK" && grep -q "sha256 \"$SHA\"" "$CASK" || { echo "publish: cask edit failed" >&2; exit 1; }
fi
brew tap | grep -qx "$TAP_NAME" || run brew tap "$TAP_NAME" "$TAP"
run brew style "$TAP"
run brew audit --cask --strict --online "$TAP_NAME/legible"
run git -C "$TAP" commit -am "legible $V"
run git -C "$TAP" push origin main

echo
echo "Published Legible $V. Users install it with:"
echo "  brew install --cask $TAP_NAME/legible"
