# Legible

A macOS Markdown reader. Opens a `.md` file instantly as a full-window rendered document, with an editor only when you ask for one, and themes that are pleasant to read.

Native Swift/AppKit, renders in WKWebView, everything bundled locally (no network at runtime). Apple Silicon, macOS 14 or later.

## Install

With Homebrew, on an Apple Silicon Mac running macOS 14 or later:

```bash
brew install --cask tom-xlsx/tap/legible
```

Legible is not notarised, so macOS may refuse to open it the first time. Dismiss the dialog, open System Settings › Privacy & Security, scroll down and click “Open Anyway”. Open Legible once so its Quick Look extension is registered. `brew upgrade --cask legible` updates it; `brew uninstall --cask --zap legible` removes it along with its settings.

Without Homebrew, download `Legible-<version>.zip` from the Releases page, unzip, and drag `Legible.app` to Applications; the same first-launch step applies.

## Build from source

Requirements: Xcode (or the Command Line Tools) with Swift 5.9+.

```bash
make install
```

That builds a Release `Legible.app`, ad-hoc signs it, copies it to `~/Applications`, and installs the `legible` command into `~/.local/bin`.

To make Legible the default app for Markdown files, choose File › Use Legible for Markdown Files… once (macOS asks you to confirm). The manual route also works: in Finder, Get Info on any `.md` file, choose Legible under “Open with”, and click “Change All…”.

Other targets:

| Target | What it does |
|---|---|
| `make app` | Build `build/Legible.app` without installing |
| `make check` | Build, run unit tests, check every theme's contrast, render the kitchen-sink fixture |
| `make snapshots` | Render `fixtures/kitchen-sink.md` in every theme to `build/snapshots/` |
| `make dist` | Zip the built app to `build/dist/` with a read-me on opening an unnotarised app |
| `make app-debug` | Debug build at `build/debug/Legible.app` |
| `make ql-shot FILE=x.md` | Screenshot the installed Quick Look preview of a file to `build/ql-shot.png` |
| `make uninstall` | Remove what `make install` put in place |
| `make release VERSION=x.y.z` | Tag a release (annotated, opens your editor for notes), then build and install |
| `make publish` | Push the tagged release: zip, GitHub release, Homebrew cask bump in `../homebrew-tap` |

Versions come from git tags only: the build derives `CFBundleShortVersionString` from `git describe` and `CFBundleVersion` from the commit count. `legible --version` prints e.g. `0.3.0 (142, a1b2c3d)`, with `-dirty` when built from uncommitted changes.

## Command line

```bash
legible README.md          # open a file
legible a.md b.md          # open several
legible https://…/NOTES.md # open a file from a URL
cat notes.md | legible -   # read from stdin
legible --version
```

A URL is downloaded to a temporary file, so relative links and images inside it won't resolve. A GitHub file page (`github.com/…/blob/…`) is fetched as the raw file, so you can paste the link straight from the browser.

For the Yazi file manager, add an opener rule that runs `legible "$@"` for `*.md`.

## Quick Look

Legible includes a Quick Look extension, so selecting a Markdown file in Finder and pressing Space shows it rendered. `make install` registers it; if nothing changes, open Legible once and try again. Previews use the default light and dark themes and follow the system appearance. They leave raw HTML out (it appears as text) and can't load images stored beside the file, because Quick Look only lets the extension read the file itself.

If another Markdown previewer is installed, macOS may keep using it. To step it aside:

```bash
pluginkit -e ignore -i <its bundle identifier>
```

`pluginkit -m -p com.apple.quicklook.preview -v` lists the candidates; `pluginkit -e default -i <id>` restores one.

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

`@appearance` (`light` or `dark`) decides which group the theme is listed under. `@contrast aaa` declares a high-contrast theme, and `@focus true` with a `--focus-dim` value turns on focus mode (only the block at the reading line is shown at full strength). A user theme with the same file name as a bundled one replaces it. View › Theme › Show User Themes Folder opens the folder; hovering a theme in that menu previews it live, and ⌘⇧T cycles through them. Keep body text at WCAG AA contrast or better, and don't rely on red versus green to tell syntax tokens apart.

## Editing

Files open in reading mode. ⌘E (or the toolbar button) opens an editor pane beside the preview: plain monospace text, live preview as you type, and scroll positions kept in step both ways. ⌘S saves; closing the pane returns to reading mode. The editor never opens on its own for an existing file.

⌘N starts a new, untitled document with the editor open and focused. ⌘⇧N does the same with whatever Markdown is on the clipboard, opening it for reading. ⌘S asks where to save; from then on it behaves like any other file (relative images resolve next to it, live reload watches it).

## Settings

⌘, opens Settings (General, Appearance, Reading, Editor, Garnish). Everything is stored in `~/Library/Application Support/Legible/settings.toml`, a commented file you can edit by hand; changes apply immediately in both directions. Legible only ever rewrites the single line a setting lives on, so your comments, ordering and any extra keys survive. If the file has a mistake, the app keeps the last good settings and shows which line is wrong. General has “Reveal Settings File” and “Reset to Defaults”. The file's format is deliberately simple: strings, numbers, booleans and `[tables]`; arrays, inline tables and multi-line strings are reported as errors rather than being rewritten. `schema = 1` at the top lets future versions migrate the file in place.

## Windows

Quitting with documents open brings them back, at the same scroll position, next time Legible starts (unless you open a specific file). Closing a window forgets it.

## Live reload

When the file changes on disk (saved from another editor, regenerated by a script), the window re-renders in place and keeps your scroll position. If you have unsaved edits in the editor pane, a small notice offers Reload or Keep Mine instead of clobbering them.

## Rendering notes

- GitHub-flavoured Markdown: tables, task lists, strikethrough, footnotes, autolinks, syntax highlighting.
- YAML front matter is shown as a small collapsed block.
- Relative images and links resolve within the document's git repository (or its folder when there is no repository). Links to other Markdown files open in Legible; external links open in your browser.
- Every code block has a copy button (hover, or Tab to it). It copies the fence's raw source, minus only the newline that ends its last line.
- Zoom with ⌘+ / ⌘− / ⌘0, find with ⌘F (⌘G and ⌘⇧G step through matches).
- ⌘⌥T (or the toolbar button) shows a table of contents built from the headings; it follows your reading position and clicking an entry jumps there. Settings › Reading can open it by default.
- An estimated reading time appears under the window title (Settings › Reading).
- Raw HTML is limited to the safe subset READMEs actually use (`details`, `summary`, `img` with `align`/`width`, `picture`, `kbd`, `sup`, `sub`, `br`, `div align`, tables). Scripts, event handlers, iframes, forms, styles and anything that could run code or phone home are stripped.

## Icebox

Not built yet, deliberately:

- Mermaid diagrams (` ```mermaid ` fences render as plain code blocks for now).
- KaTeX math (` ```math ` fences likewise).

## Licence

GPLv3. See `LICENSE`.
