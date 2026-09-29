#!/usr/bin/env python3
"""Checks every theme in a directory for contrast and colour-vision safety.

For each *.css theme (except _template.css):
  * every variable the app relies on is defined;
  * body text, headings, links, muted text, code and the copy button meet
    WCAG AA (4.5:1) against their backgrounds — or AAA (7:1) when the theme
    header says `@contrast aaa`;
  * every syntax token colour meets 4.5:1 on the code-block background;
  * no two syntax token colours are distinguishable only by the red/green
    axis: after simulating deuteranopia they must still differ by ΔE ≥ 12.
    Exempt: identical colours (a deliberate "same colour"), tokens already
    set apart by weight or style (bold keywords and tags, italic comments),
    the muted trio comment/meta/punct among themselves, and numbers (digits
    identify themselves).

Exit status is non-zero if anything fails. Usage: check-themes.py Resources/themes
"""
import math
import re
import sys
from pathlib import Path

REQUIRED = """
bg fg fg-muted link link-hover heading rule
quote-fg quote-border quote-bg
table-border table-head-bg table-stripe
code-inline-fg code-inline-bg
code-fg code-bg code-border code-label
copy-fg copy-bg copy-border copy-hover-bg copy-hover-fg
selection-bg selection-fg
font-body font-mono font-size line-height measure
hl-comment hl-keyword hl-string hl-number hl-function hl-type hl-variable
hl-attr hl-tag hl-meta hl-punct hl-addition-bg hl-deletion-bg
hl-keyword-weight hl-comment-style
""".split()

TOKENS = ["hl-comment", "hl-keyword", "hl-string", "hl-number", "hl-function",
          "hl-type", "hl-variable", "hl-attr", "hl-tag", "hl-meta", "hl-punct"]

DEUTAN = [  # Machado et al. 2009, deuteranopia (severity 1.0), linear RGB
    [0.367322, 0.860646, -0.227968],
    [0.280085, 0.672501, 0.047413],
    [-0.011820, 0.042940, 0.968881],
]


def parse(path: Path):
    text = path.read_text()
    meta = dict(re.findall(r"@(\w+)\s+([^\n*]+)", text))
    root = re.search(r":root\s*{(.*?)}", text, re.S)
    if not root:
        return meta, {}
    vars_ = {}
    for m in re.finditer(r"--([\w-]+)\s*:\s*([^;]+);", root.group(1)):
        vars_[m.group(1)] = m.group(2).strip()
    return {k: v.strip() for k, v in meta.items()}, vars_


def hex_to_rgb(value):
    m = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})", value.strip())
    if not m:
        return None
    h = m.group(1)
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(rgb):
    r, g, b = (linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def simulate_deutan(rgb):
    lin = [linear(c) for c in rgb]
    out = [sum(DEUTAN[i][j] * lin[j] for j in range(3)) for i in range(3)]
    return [min(max(v, 0.0), 1.0) for v in out]


def lab(lin_rgb):
    r, g, b = lin_rgb
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 1.0
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116

    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e(a, b):
    return math.sqrt(sum((p - q) ** 2 for p, q in zip(a, b)))


def check(path: Path):
    meta, v = parse(path)
    problems = []
    missing = [k for k in REQUIRED if k not in v]
    if missing:
        problems.append(f"missing variables: {', '.join(missing)}")
        return meta, problems

    def rgb(name):
        c = hex_to_rgb(v[name])
        if c is None:
            problems.append(f"--{name} is not a hex colour ({v[name]})")
        return c

    minimum = 7.0 if meta.get("contrast", "").lower() == "aaa" else 4.5
    pairs = [
        ("fg", "bg", minimum), ("heading", "bg", minimum), ("fg-muted", "bg", 4.5),
        ("link", "bg", 4.5), ("link-hover", "bg", 4.5),
        ("quote-fg", "quote-bg", 4.5),
        ("code-inline-fg", "code-inline-bg", 4.5),
        ("code-fg", "code-bg", minimum), ("code-label", "code-bg", 3.0),
        ("copy-fg", "copy-bg", 4.5), ("copy-hover-fg", "copy-hover-bg", 4.5),
        ("selection-fg", "selection-bg", 4.5),
        ("fg", "table-stripe", minimum), ("fg", "table-head-bg", minimum),
    ]
    for fg, bg, need in pairs:
        a, b = rgb(fg), rgb(bg)
        if a and b:
            ratio = contrast(a, b)
            if ratio < need:
                problems.append(f"--{fg} on --{bg}: {ratio:.2f}:1 (need {need})")

    code_bg = rgb("code-bg")
    token_colours = {}
    for name in TOKENS:
        c = rgb(name)
        if c and code_bg:
            token_colours[name] = c
            ratio = contrast(c, code_bg)
            if ratio < 4.5:
                problems.append(f"--{name} on --code-bg: {ratio:.2f}:1 (need 4.5)")
    for name in ("hl-addition-bg", "hl-deletion-bg"):
        c = rgb(name)
        code_fg = rgb("code-fg")
        if c and code_fg and contrast(code_fg, c) < 4.5:
            problems.append(f"--code-fg on --{name}: {contrast(code_fg, c):.2f}:1 (need 4.5)")

    style_distinct = set()
    if int(re.sub(r"\D", "", v.get("hl-keyword-weight", "400")) or 400) >= 600:
        style_distinct |= {"hl-keyword", "hl-tag"}
    if v.get("hl-comment-style", "normal") != "normal":
        style_distinct.add("hl-comment")
    muted = {"hl-comment", "hl-meta", "hl-punct"}
    self_evident = {"hl-number"}

    names = list(token_colours)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            ca, cb = token_colours[a], token_colours[b]
            if ca == cb or {a, b} & style_distinct or {a, b} & self_evident or {a, b} <= muted:
                continue
            de = delta_e(lab(simulate_deutan(ca)), lab(simulate_deutan(cb)))
            if de < 12:
                problems.append(f"--{a} and --{b} look alike with deuteranopia (ΔE {de:.1f} < 12)")
    return meta, problems


def main():
    directory = Path(sys.argv[1] if len(sys.argv) > 1 else "Resources/themes")
    failed = 0
    themes = sorted(p for p in directory.glob("*.css") if not p.name.startswith("_"))
    for path in themes:
        meta, problems = check(path)
        label = f"{meta.get('name', path.stem)} ({path.name})"
        if problems:
            failed += 1
            print(f"FAIL {label}")
            for p in problems:
                print(f"     {p}")
        else:
            print(f"ok   {label}")
    print(f"{len(themes) - failed}/{len(themes)} themes pass")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
