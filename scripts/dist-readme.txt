Legible @VERSION@
A Markdown reader for macOS. Apple Silicon, macOS 14 or later.

Opening it the first time
  This copy is not notarised with Apple, so macOS will refuse it once.
  Either:
    1. Double-click Legible.app, dismiss the warning, then open
       System Settings > Privacy & Security, scroll down, and click
       "Open Anyway" next to Legible. Confirm, and it opens normally after that.
  Or, in Terminal, remove the quarantine flag and open it:
       xattr -dr com.apple.quarantine ~/Downloads/Legible.app
       open ~/Downloads/Legible.app

Then
  Drag Legible.app to your Applications folder (or ~/Applications).
  To make it the default for .md files: File > Use Legible for Markdown Files...
  For a `legible` command in Terminal: Legible > Settings... > General > Install.

Settings live in ~/Library/Application Support/Legible/settings.toml.
Licensed under the GPLv3.
