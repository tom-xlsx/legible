Legible @VERSION@
A Markdown reader for macOS. Apple Silicon, macOS 14 or later.

The easy way, if you use Homebrew
  brew install --cask tom-xlsx/tap/legible
  (then see "Opening it for the first time" below, which still applies)

Opening it for the first time
  This copy is not notarised by Apple, so macOS will refuse to open it
  the first time. Do one of the following:

  Either: double-click Legible.app and dismiss the warning, then open
       System Settings > Privacy & Security, scroll down, and click
       "Open Anyway" next to Legible. Confirm, and it will open normally
       from then on.

  Or: in Terminal, remove the quarantine flag and open it:
       xattr -dr com.apple.quarantine ~/Downloads/Legible.app
       open ~/Downloads/Legible.app

Then
  Drag Legible.app to your Applications folder (or ~/Applications).
  To make it the default for .md files: File > Use Legible for Markdown Files...
  For a `legible` command in Terminal: Legible > Settings... > General > Install.

Settings live in ~/Library/Application Support/Legible/settings.toml.
Licensed under the GPLv3.
