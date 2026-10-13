#!/bin/bash
# Builds Legible in Release, assembles build/Legible.app and ad-hoc signs it.
# Version numbers come from git tags only (see scripts/version.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
if [ "$CONFIG" = "debug" ]; then APP="$ROOT/build/debug/Legible.app"; else APP="$ROOT/build/Legible.app"; fi
CONTENTS="$APP/Contents"

eval "$("$ROOT/scripts/version.sh")"   # sets VERSION, BUILD, DESCRIPTION
echo "Building Legible $DESCRIPTION"

swift build -c "$CONFIG" --arch arm64 -Xswiftc -warnings-as-errors
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Legible"

rm -rf "$APP"
mkdir -p "$(dirname "$APP")" "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/Legible"

sed -e "s|@VERSION@|$VERSION|" \
    -e "s|@BUILD@|$BUILD|" \
    -e "s|@DESCRIPTION@|$DESCRIPTION|" \
    "$ROOT/Resources/Info.plist" > "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

cp -R "$ROOT/Resources/web"    "$CONTENTS/Resources/web"
cp -R "$ROOT/Resources/themes" "$CONTENTS/Resources/themes"
cp -R "$ROOT/Resources/moth"   "$CONTENTS/Resources/moth"
cp    "$ROOT/build/Legible.icns" "$CONTENTS/Resources/Legible.icns"
cp    "$ROOT/Resources/icon/legible.svg" "$CONTENTS/Resources/legible.svg"
mkdir -p "$CONTENTS/Resources/bin"
install -m 755 "$ROOT/scripts/legible" "$CONTENTS/Resources/bin/legible"

# Quick Look preview extension. Signed first, with its sandbox entitlements (required
# for any plug-in; without them pkd ignores it silently), then the app, never --deep.
QLBIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/LegibleQuickLook"
APPEX="$CONTENTS/PlugIns/LegibleQuickLook.appex"
mkdir -p "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp "$QLBIN" "$APPEX/Contents/MacOS/LegibleQuickLook"
sed -e "s|@VERSION@|$VERSION|" -e "s|@BUILD@|$BUILD|" \
    "$ROOT/Resources/QuickLook/Info.plist" > "$APPEX/Contents/Info.plist"
printf 'XPC!????' > "$APPEX/Contents/PkgInfo"
# The extension renders with the same core and CSS as the page, from its own copy.
cp "$ROOT/Resources/web/legible-core.js" "$ROOT/Resources/web/legible.css" "$APPEX/Contents/Resources/"
cp -R "$ROOT/Resources/web/vendor" "$APPEX/Contents/Resources/vendor"
mkdir -p "$APPEX/Contents/Resources/themes"
cp "$ROOT/Resources/themes/oat-milk.css" "$ROOT/Resources/themes/burnt-toast.css" "$APPEX/Contents/Resources/themes/"
codesign --force --sign - --timestamp=none \
    --entitlements "$ROOT/Resources/QuickLook/LegibleQuickLook.entitlements" "$APPEX"
codesign -d --entitlements :- "$APPEX" 2>/dev/null | grep -q app-sandbox \
    || { echo "build-app: the Quick Look extension lost its sandbox entitlement" >&2; exit 1; }

codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"
