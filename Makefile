APP      := build/Legible.app
ICNS     := build/Legible.icns
INSTALL  := $(HOME)/Applications/Legible.app
BINDIR   := $(HOME)/.local/bin
FIXTURE  := fixtures/kitchen-sink.md

.PHONY: all build app icon install check test snapshots release clean

all: app

## Compile only (Release, arm64, warnings are errors).
build:
	swift build -c release --arch arm64 -Xswiftc -warnings-as-errors

## Assemble and ad-hoc sign build/Legible.app.
app: icon
	scripts/build-app.sh

## Render the app icon from Resources/icon/legible.svg.
icon: $(ICNS)
$(ICNS): Resources/icon/legible.svg scripts/make-icon.swift
	@mkdir -p build
	swift scripts/make-icon.swift Resources/icon/legible.svg $(ICNS)

## Build, copy to ~/Applications, install the `legible` CLI.
install: app
	rm -rf "$(INSTALL)"
	cp -R "$(APP)" "$(INSTALL)"
	mkdir -p "$(BINDIR)"
	install -m 755 scripts/legible "$(BINDIR)/legible"
	@echo "Installed $(INSTALL) and $(BINDIR)/legible"
	@echo "To make Legible the default app for Markdown: open a .md file, then Legible › Settings › General › “Use Legible for Markdown files”,"
	@echo "or in Finder: Get Info on any .md file › Open with › Legible › Change All…"

## Unit tests.
test:
	swift test

## Everything that must pass before a commit: build, tests, theme checks, fixture render.
check: app test
	python3 scripts/check-themes.py Resources/themes
	$(APP)/Contents/MacOS/Legible --selftest=$(FIXTURE)
	$(APP)/Contents/MacOS/Legible --snapshot=$(FIXTURE) --out=build/check-oat-milk.png --theme=oat-milk
	$(APP)/Contents/MacOS/Legible --snapshot=$(FIXTURE) --out=build/check-burnt-toast.png --theme=burnt-toast
	@echo "check: OK"

## Snapshot the kitchen sink in every bundled theme to build/snapshots/.
snapshots: app
	@mkdir -p build/snapshots
	@for f in Resources/themes/*.css; do \
	  id=$$(basename $$f .css); [ "$$id" = "_template" ] && continue; \
	  $(APP)/Contents/MacOS/Legible --snapshot=$(FIXTURE) --out=build/snapshots/$$id.png --theme=$$id || exit 1; \
	done
	@echo "Snapshots in build/snapshots/"

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
