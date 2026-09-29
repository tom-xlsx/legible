# Legible

A macOS Markdown reader. Opens a `.md` file instantly as a full-window rendered document, with an editor only when you ask for one, and themes that are pleasant to read.

Native Swift/AppKit, renders in WKWebView, everything bundled locally (no network at runtime). Apple Silicon, macOS 14 or later.

## Build and install

Requirements: Xcode (or the Command Line Tools) with Swift 5.9+.

```bash
make install
```

That builds a Release `Legible.app`, ad-hoc signs it, copies it to `~/Applications`, and installs the `legible` command into `~/.local/bin`.

To make Legible the default app for Markdown files: in Finder, Get Info on any `.md` file, choose Legible under “Open with”, and click “Change All…”.

Other targets:

| Target | What it does |
|---|---|
| `make app` | Build `build/Legible.app` without installing |
| `make check` | Build, run unit tests, check every theme's contrast, render the kitchen-sink fixture |
| `make snapshots` | Render `fixtures/kitchen-sink.md` in every theme to `build/snapshots/` |
| `make release VERSION=x.y.z` | Tag a release (annotated, opens your editor for notes), then build and install |

Versions come from git tags only: the build derives `CFBundleShortVersionString` from `git describe` and `CFBundleVersion` from the commit count. `legible --version` prints e.g. `0.3.0 (142, a1b2c3d)`, with `-dirty` when built from uncommitted changes.

## Command line

```bash
legible README.md          # open a file
legible a.md b.md          # open several
cat notes.md | legible -   # read from stdin
legible --version
```

For the Yazi file manager, add an opener rule that runs `legible "$@"` for `*.md`.

## Themes

Themes are plain CSS files. Legible ships 14; put your own in `~/Library/Application Support/Legible/Themes/` and they appear in the View › Theme menu, reloading live when the file changes. A commented `_template.css` documenting every variable is written there on first launch.

A theme is a header comment plus a `:root` block:

```css
/* @name Flat White
   @appearance light
   @description Milky and calm. */
:root {
  --bg: #f4f1ea;
  --fg: #2a2926;
  /* … see _template.css for the full list … */
}
```

`@appearance` (`light` or `dark`) decides which group the theme is listed under. Keep body text at WCAG AA contrast or better, and don't rely on red versus green to tell syntax tokens apart.

## Rendering notes

- GitHub-flavoured Markdown: tables, task lists, strikethrough, footnotes, autolinks, syntax highlighting.
- YAML front matter is shown as a small collapsed block.
- Relative images and links resolve within the document's git repository (or its folder when there is no repository). Links to other Markdown files open in Legible; external links open in your browser.
- Raw HTML is limited to the safe subset READMEs actually use (`details`, `summary`, `img` with `align`/`width`, `picture`, `kbd`, `sup`, `sub`, `br`, `div align`, tables). Scripts, event handlers, iframes, forms, styles and anything that could run code or phone home are stripped.

## Icebox

Not built yet, deliberately:

- Mermaid diagrams (` ```mermaid ` fences render as plain code blocks for now).
- KaTeX math (` ```math ` fences likewise).

## Licence

GPLv3. See `LICENSE`.
