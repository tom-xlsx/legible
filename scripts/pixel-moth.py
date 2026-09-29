#!/usr/bin/env python3
"""Builds the Marmalade pixel moth sprite sheet from frames.txt.

Reads Resources/moth/marmalade-pixel/frames.txt (16×16 character grids), maps
each character to a colour from the Marmalade theme, upscales 2× with hard
pixels, and writes sheet.png (frames side by side) plus frames.json (frame
name → index). Run it after editing frames.txt; the outputs are committed.
"""
import json
import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "Resources/moth/marmalade-pixel"
THEME = ROOT / "Resources/themes/marmalade.css"
SCALE = 2
SIZE = 16


def theme_vars():
    css = THEME.read_text()
    return dict(re.findall(r"--([\w-]+)\s*:\s*([^;]+);", css))


def hex_rgb(h):
    h = h.strip().lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def palette():
    v = theme_vars()
    bg, fg, muted, link = hex_rgb(v["bg"]), hex_rgb(v["fg"]), hex_rgb(v["fg-muted"]), hex_rgb(v["link"])
    cream = hex_rgb(v.get("hl-string", "#fff0d0"))
    return {
        "a": muted, "b": muted,
        "w": fg, "s": mix(fg, bg, 0.28), "m": mix(muted, bg, 0.35),
        "e": cream, "p": bg, "g": link, "k": link, "n": cream, "h": link, "l": bg,
    }


def parse_frames(text):
    frames, name, rows = [], None, []
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        if line.startswith("@"):
            if name:
                frames.append((name, rows))
            name, rows = line[1:].strip(), []
        else:
            rows.append(line.rstrip())
    if name:
        frames.append((name, rows))
    for fname, grid in frames:
        assert len(grid) == SIZE, f"{fname}: {len(grid)} rows, want {SIZE}"
        for r in grid:
            assert len(r) == SIZE, f"{fname}: row '{r}' is {len(r)} wide, want {SIZE}"
    return frames


def write_png(path, width, height, rgba_rows):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    raw = b"".join(b"\x00" + row for row in rgba_rows)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def main():
    frames = parse_frames((PACK / "frames.txt").read_text())
    pal = palette()
    cell = SIZE * SCALE
    width, height = cell * len(frames), cell
    rows = []
    for py in range(height):
        row = bytearray()
        for fi, (_, grid) in enumerate(frames):
            for px in range(cell):
                ch = grid[py // SCALE][px // SCALE]
                if ch == ".":
                    row += b"\x00\x00\x00\x00"
                else:
                    r, g, b = pal[ch]
                    row += bytes((r, g, b, 255))
        rows.append(bytes(row))
    write_png(PACK / "sheet.png", width, height, rows)
    (PACK / "frames.json").write_text(json.dumps({name: i for i, (name, _) in enumerate(frames)}, indent=2) + "\n")
    print(f"Wrote {PACK / 'sheet.png'} ({len(frames)} frames, {width}×{height})")


if __name__ == "__main__":
    sys.exit(main())
