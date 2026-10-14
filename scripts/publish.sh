#!/bin/bash
# Publishes the release HEAD is tagged with: builds the zip, pushes, creates the
# GitHub release, then bumps the Homebrew cask in the tap and pushes that too.
#
#   make release VERSION=x.y.z    # tag + install (existing)
#   make publish                  # this script
#
# LEGIBLE_TAP points at the tap checkout (default: ../homebrew-tap).
# --dry-run (or DRY_RUN=1) prints every command instead of running it. If an earlier run was
# interrupted after the GitHub release was created, running again resumes from
# the uploaded zip (VERSION=x.y.z if HEAD has since moved past the tag).
set -euo pipefail
cd "$(dirname "$0")/.."

DRY=""
{ [ "${1:-}" = "--dry-run" ] || [ -n "${DRY_RUN:-}" ]; } && DRY="echo + "
run() { if [ -n "$DRY" ]; then echo "+ $*"; else "$@"; fi; }

TAP="${LEGIBLE_TAP:-$PWD/../homebrew-tap}"
TAP_NAME="tom-xlsx/tap"
CASK="$TAP/Casks/legible.rb"

# -- preconditions ---------------------------------------------------------
[ -z "$(git status --porcelain)" ] || { echo "publish: the tree is not clean" >&2; exit 1; }
# Normally HEAD is the tagged commit. VERSION=x.y.z lets a later commit finish a
# release whose GitHub release already exists (nothing is rebuilt in that case).
if [ -n "${VERSION:-}" ]; then
  TAG="v$VERSION"
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "publish: no tag $TAG" >&2; exit 1; }
  gh release view "$TAG" >/dev/null 2>&1 || { echo "publish: VERSION= only resumes a release that already exists on GitHub; check out $TAG to publish it" >&2; exit 1; }
else
  TAG="$(git describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null)" || { echo "publish: HEAD is not tagged (make release VERSION=x.y.z first, or VERSION=x.y.z to resume)" >&2; exit 1; }
fi
V="${TAG#v}"
[ -f "$CASK" ] || { echo "publish: no cask at $CASK (set LEGIBLE_TAP)" >&2; exit 1; }
# The cask file is the only thing this script edits, so it may be left modified by an earlier, interrupted run.
[ -z "$(git -C "$TAP" status --porcelain | grep -v ' Casks/legible.rb$')" ] || { echo "publish: the tap at $TAP has changes other than the cask" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "publish: gh is not logged in (gh auth login)" >&2; exit 1; }

ZIP="build/dist/Legible-$V.zip"
if gh release view "$TAG" >/dev/null 2>&1; then
  # Already published (an earlier run got this far): the uploaded zip is the truth,
  # so take its checksum rather than rebuilding, which would not be byte-identical.
  echo "publish: release $TAG exists; resuming from its uploaded zip"
  if [ -n "$DRY" ]; then
    SHA='<sha256 of the uploaded zip>'
  else
    tmp="$(mktemp -d)"
    gh release download "$TAG" --pattern "Legible-$V.zip" --dir "$tmp" || { echo "publish: release $TAG has no Legible-$V.zip" >&2; exit 1; }
    SHA="$(shasum -a 256 "$tmp/Legible-$V.zip" | cut -d' ' -f1)"
    rm -rf "$tmp"
  fi
else
  # -- build, checksum, push, release ---------------------------------------
  run make dist
  [ -n "$DRY" ] || [ -f "$ZIP" ] || { echo "publish: $ZIP was not built" >&2; exit 1; }
  SHA="$([ -n "$DRY" ] && echo '<sha256>' || shasum -a 256 "$ZIP" | cut -d' ' -f1)"
  run git push origin main
  run git push origin "$TAG"
  run gh release create "$TAG" "$ZIP" --title "Legible $V" --notes-from-tag --verify-tag
fi

# -- tap bump ---------------------------------------------------------------
if [ -n "$DRY" ]; then
  echo "+ sed -i '' version=$V sha256=$SHA $CASK"
else
  sed -i '' -e "s/^  version \".*\"/  version \"$V\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
  grep -q "version \"$V\"" "$CASK" && grep -q "sha256 \"$SHA\"" "$CASK" || { echo "publish: cask edit failed" >&2; exit 1; }
fi
run brew style "$TAP"
if [ -n "$DRY" ] || ! git -C "$TAP" diff --quiet; then run git -C "$TAP" commit -am "legible $V"; fi
run git -C "$TAP" push origin main
# Homebrew keeps its own clone of the tap, so the audit runs on what was just pushed.
brew tap | grep -qx "$TAP_NAME" || run brew tap "$TAP_NAME" "$TAP"
run git -C "$(brew --repository "$TAP_NAME")" pull -q --ff-only
run brew audit --cask --strict --online "$TAP_NAME/legible" \
  || { echo "publish: the cask is pushed but failed the audit above; fix $CASK, commit, push, and re-run the audit" >&2; exit 1; }

echo
echo "Published Legible $V. Users install it with:"
echo "  brew install --cask $TAP_NAME/legible"
