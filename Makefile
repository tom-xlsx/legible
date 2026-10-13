APP      := build/Legible.app
ICNS     := build/Legible.icns
INSTALL  := $(HOME)/Applications/Legible.app
BINDIR   := $(HOME)/.local/bin
FIXTURE  := fixtures/kitchen-sink.md
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Checks and snapshots run against a throwaway settings file, never yours.
export LEGIBLE_SETTINGS := $(CURDIR)/build/check-settings.toml

.PHONY: all build app app-debug icon install check test snapshots ql-shot release dist clean

all: app

## Compile only (Release, arm64, warnings are errors).
build:
	swift build -c release --arch arm64 -Xswiftc -warnings-as-errors

## Assemble and ad-hoc sign build/Legible.app.
app: icon
	scripts/build-app.sh

## Debug build with the hidden Moth menu, at build/debug/Legible.app.
app-debug: icon
	CONFIG=debug scripts/build-app.sh

## Render the app icon from Resources/icon/legible.svg.
icon: $(ICNS)
$(ICNS): Resources/icon/legible.svg scripts/make-icon.swift
	@mkdir -p build
	swift scripts/make-icon.swift Resources/icon/legible.svg $(ICNS)

## Build, copy to ~/Applications, install the `legible` CLI.
install: app
	-pluginkit -r "$(INSTALL)/Contents/PlugIns/LegibleQuickLook.appex" 2>/dev/null
	rm -rf "$(INSTALL)"
	cp -R "$(APP)" "$(INSTALL)"
	mkdir -p "$(BINDIR)"
	install -m 755 scripts/legible "$(BINDIR)/legible"
	$(LSREGISTER) -f "$(INSTALL)"
	pluginkit -a "$(INSTALL)/Contents/PlugIns/LegibleQuickLook.appex"
	pluginkit -e use -i io.github.tom-xlsx.Legible.QuickLook
	qlmanage -r >/dev/null 2>&1; qlmanage -r cache >/dev/null 2>&1
	@echo "Installed $(INSTALL) and $(BINDIR)/legible"
	@echo "One-time step to make Legible the default for .md files: File › Use Legible for Markdown Files…"

## Unit tests.
test:
	swift test

## Everything that must pass before a commit: build, tests, theme checks, fixture render.
check: app test
	rm -f build/check-settings.toml
	python3 scripts/check-themes.py Resources/themes
	$(APP)/Contents/MacOS/Legible --selftest=$(FIXTURE)
	$(APP)/Contents/MacOS/Legible --moth-validate
	$(APP)/Contents/MacOS/Legible --moth-selftest=$(FIXTURE)
	$(APP)/Contents/MacOS/Legible --snapshot=$(FIXTURE) --out=build/check-oat-milk.png --theme=oat-milk
	$(APP)/Contents/MacOS/Legible --snapshot=$(FIXTURE) --out=build/check-burnt-toast.png --theme=burnt-toast
	$(APP)/Contents/MacOS/Legible --quicklook=$(FIXTURE) --out=build/check-quicklook.png
	@echo "check: OK"

## Snapshot the kitchen sink in every bundled theme to build/snapshots/.
snapshots: app
	@mkdir -p build/snapshots
	@for f in Resources/themes/*.css; do \
	  id=$$(basename $$f .css); [ "$$id" = "_template" ] && continue; \
	  $(APP)/Contents/MacOS/Legible --snapshot=$(FIXTURE) --out=build/snapshots/$$id.png --theme=$$id || exit 1; \
	done
	swift scripts/contact-sheet.swift build/snapshots/all.png --columns 4 --width 420 build/snapshots/*.png
	@echo "Snapshots in build/snapshots/ (all.png is the contact sheet)"

## Screenshot the installed Quick Look preview of a file: make ql-shot FILE=notes.md
ql-shot:
	@[ -n "$(FILE)" ] || { echo "usage: make ql-shot FILE=path.md"; exit 1; }
	scripts/ql-shot.sh "$(FILE)" build/ql-shot.png

## Zip the built app for sharing, with the version in the name and a note on opening it.
dist: app
	@mkdir -p build/dist
	@eval "$$(scripts/version.sh)"; \
	  zip="build/dist/Legible-$$VERSION.zip"; rm -f "$$zip"; \
	  ditto -c -k --keepParent "$(APP)" "$$zip"; \
	  sed "s/@VERSION@/$$DESCRIPTION/" scripts/dist-readme.txt > "build/dist/Read me first.txt"; \
	  echo "Wrote $$zip and build/dist/Read me first.txt"

## Tag a release (annotated; opens your editor for the notes), then build and install.
release:
	@[ -n "$(VERSION)" ] || { echo "usage: make release VERSION=x.y.z"; exit 1; }
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "VERSION must be x.y.z"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "refusing: uncommitted changes"; exit 1; }
	@[ -z "$$(git status --porcelain)" ] || { echo "refusing: untracked files present"; exit 1; }
	git tag -a "v$(VERSION)"
	$(MAKE) install

clean:
	rm -rf build .build
