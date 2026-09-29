# Moth art packs

The moth's behaviour never touches artwork. It calls a small renderer interface
(`setPose`, `lookAt`, `blink`, `flyTo`, `land`, `takeOff`, `setScale`,
`setPalette`, `setVisible`), and an **art pack** decides what those calls look
like. This folder holds the built-in packs; a pack of your own placed in
`~/Library/Application Support/Legible/Moth/` (a folder containing
`manifest.json`) replaces the built-in one. It is loaded at launch and whenever
a document window reloads. An invalid pack is reported in the same notice bar as
a broken settings file, and the built-in pack is used instead.

Regenerate the review sheet for any pack with:

```
Legible.app/Contents/MacOS/Legible --moth-sheet=out.png [--pack=/path/to/pack] [--theme=oat-milk,decaf]
```

and validate one with `--moth-validate[=/path/to/pack]`.

## manifest.json

Common fields:

| Field | Meaning |
|---|---|
| `name` | Shown nowhere but logs and the About box. |
| `type` | `svg-rig` or `spritesheet` (a `rive` type is reserved for later). |
| `format` | Manifest format version, currently `1`. |
| `asset` | The artwork file, relative to the manifest. |
| `size` | Rendered height in CSS pixels at zoom 1. 24–32 is the intended range. |
| `anchors` | Points in asset coordinates: `feet` (contact point when perched), `centre`, `eyeLeft`, `eyeRight`, `book`. |
| `poses` | One entry per required pose (list below). A pack may map several poses to the same art. |

### Required poses

`perch-idle`, `perch-reading` (book open), `page-turn`, `doze`, `yawn`, `wake`,
`startled`, `cling` (wings ruffled), `smooth-down`, `disapprove`, `glance`
(direction comes from `lookAt`), `nod`, `magnifier`, `wave`, `close-book`,
`take-off`, `fly` (wing-flap cycle), `land`.

### Variants

Theme looks are flags, not poses. The app asks for `glasses-large` (Big
Breakfast), `eyes-drowsy` (Decaf) and `body-faint` (Midnight Snack). An
`svg-rig` pack declares how each flag changes its parts under `variants`; a
`spritesheet` pack may ignore them. Marmalade uses the pixel pack instead.

## Palette tokens

Art should use these CSS variables rather than fixed colours. Legible derives
defaults from every theme (body from `--fg-muted`, wings from `--bg` mixed
toward `--fg-muted` so they stand out by lightness, glasses and book from
`--link`), and any theme can override them in its `:root` block:

`--moth-body`, `--moth-wing`, `--moth-wing-shade`, `--moth-wing-mark`,
`--moth-eye`, `--moth-eye-white`, `--moth-glasses`, `--moth-book`, `--moth-page`.

## `svg-rig` packs (bartholomew/)

The asset is one SVG whose parts are `<g id="…">` groups. The manifest lists
every part with its `pivot` (the point it rotates and scales around) and
whether it is `hidden` by default:

```json
"parts": { "wing-left": { "pivot": [31.5, 23] }, "book-open": { "pivot": [32, 27], "hidden": true } }
```

Poses and variants are tables of per-part changes applied on top of the rest
state: `rotate` (degrees), `translate` ([x, y] in asset units), `scale`,
`visible`, `opacity`. A pose only lists what differs:

```json
"doze": { "eyes": { "visible": false }, "lids": { "visible": true }, "antenna-left": { "rotate": -35 } }
```

`fly` may be paired with a `fly-2` pose; the renderer alternates them for the
flap cycle. `headGroup` names the parts that move together for nods and
glances; `pupils` names the elements whose `cx`/`cy` shift for `lookAt`, by up
to `pupilRange` units.

Parts in Bartholomew: `antenna-left`, `antenna-right`, `arm-wave`, `tail`,
`wing-left`, `wing-right`, `thorax`, `head`, `eyes` (with `eye-left`,
`eye-right`, `pupil-left`, `pupil-right`), `half-lids`, `lids`, `glasses`,
`magnifier`, `book-open`, `page-flip`, `book-closed`.

## `spritesheet` packs (marmalade-pixel/)

The asset is a PNG of equal-sized frames laid out left to right. `frameSize`
gives the frame size in pixels, `pixelScale` how many image pixels make one art
pixel (the sheet is drawn with hard edges, no smoothing), and `frameIndex`
names a JSON file mapping frame names to column numbers. Each pose lists its
`frames` by name and an optional `fps` for cycling:

```json
"fly": { "frames": ["fly", "fly-2"], "fps": 8 }
```

The pixel edition's source of truth is `frames.txt`, a set of 16×16 character
grids; `scripts/pixel-moth.py` turns it into `sheet.png` and `frames.json`
using the Marmalade palette. Edit the text, run the script, commit both.

## Validation

At load time and in `make check`, a pack must have: every required pose, all
five anchors, an asset that exists, a `size` between 12 and 96, and (svg-rig)
a `parts` table whose ids all exist in the SVG, or (spritesheet) frame names
that exist in the index and fit inside the image.
