#!/bin/bash
# Screenshot a Quick Look preview of FILE to OUT.png using the installed extension.
#   scripts/ql-shot.sh fixtures/kitchen-sink.md build/ql.png
set -euo pipefail
FILE="$1"; OUT="$2"
qlmanage -r cache >/dev/null 2>&1 || true
qlmanage -p "$FILE" >/dev/null 2>"${OUT%.png}.log" &
QL=$!
sleep 3
WID="$(swift - <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "qlmanage" {
    let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    if (b["Width"] ?? 0) > 200, let n = w[kCGWindowNumber as String] as? Int { print(n); break }
}
SWIFT
)"
[ -n "$WID" ] || { kill $QL 2>/dev/null; echo "ql-shot: no qlmanage window found" >&2; exit 1; }
screencapture -x -l "$WID" "$OUT"
kill $QL 2>/dev/null || true
echo "Wrote $OUT"
