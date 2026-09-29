#!/bin/bash
# Builds Legible in Release, assembles build/Legible.app and ad-hoc signs it.
# Version numbers come from git tags only (see scripts/version.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Legible.app"
CONTENTS="$APP/Contents"

eval "$("$ROOT/scripts/version.sh")"   # sets VERSION, BUILD, DESCRIPTION
echo "Building Legible $DESCRIPTION"

swift build -c release --arch arm64 -Xswiftc -warnings-as-errors
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Legible"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
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

codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"
