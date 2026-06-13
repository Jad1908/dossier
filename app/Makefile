# Build Dossier.app from the Swift package.
#
# `swift build` produces a plain executable; macOS needs a .app bundle (with an
# Info.plist) to run it as a real windowed app with a Dock icon and menu bar.
# `make app` builds release and assembles that bundle.

APP_NAME = Dossier
BUNDLE   = $(APP_NAME).app
CONFIG   = release
BIN      = .build/$(CONFIG)/$(APP_NAME)

.PHONY: all app build run icon sign clean dev-engine

all: app

build:
	swift build -c $(CONFIG)

# Install the `dossier` CLI engine editable, pointing at this repo's working
# tree. The app shells out to `dossier` for every preview, so its engine and the
# app must agree on where specs live (`.dossier/`). An editable install means
# source edits under ../src take effect immediately — no reinstall after each
# change. Re-run only if dependencies change. Requires `uv`.
dev-engine:
	uv tool install --force --reinstall --no-cache --editable --from .. dossier
	@echo "Installed editable dossier engine → $$(command -v dossier)"

# Generate AppIcon.icns from a 1024x1024 Icon.png (provide your own logo there).
# Skipped automatically by `app` when Icon.png is absent.
icon: Icon.png
	rm -rf AppIcon.iconset && mkdir AppIcon.iconset
	sips -z 16 16     Icon.png --out AppIcon.iconset/icon_16x16.png      >/dev/null
	sips -z 32 32     Icon.png --out AppIcon.iconset/icon_16x16@2x.png   >/dev/null
	sips -z 32 32     Icon.png --out AppIcon.iconset/icon_32x32.png      >/dev/null
	sips -z 64 64     Icon.png --out AppIcon.iconset/icon_32x32@2x.png   >/dev/null
	sips -z 128 128   Icon.png --out AppIcon.iconset/icon_128x128.png    >/dev/null
	sips -z 256 256   Icon.png --out AppIcon.iconset/icon_128x128@2x.png >/dev/null
	sips -z 256 256   Icon.png --out AppIcon.iconset/icon_256x256.png    >/dev/null
	sips -z 512 512   Icon.png --out AppIcon.iconset/icon_256x256@2x.png >/dev/null
	sips -z 512 512   Icon.png --out AppIcon.iconset/icon_512x512.png    >/dev/null
	cp Icon.png       AppIcon.iconset/icon_512x512@2x.png
	iconutil -c icns AppIcon.iconset -o AppIcon.icns
	rm -rf AppIcon.iconset
	@echo "Built AppIcon.icns"

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	@if [ -f Icon.png ]; then $(MAKE) icon; fi
	@if [ -f AppIcon.icns ]; then cp AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns; \
		echo "Bundled AppIcon.icns"; else echo "No Icon.png — building without an app icon"; fi
	@# Ad-hoc sign so the bundle launches without the "damaged" prompt locally.
	codesign --force --deep --sign - $(BUNDLE) >/dev/null 2>&1 || true
	@echo "Built $(BUNDLE)"

# Sign with a Developer ID identity for sharing (override IDENTITY=...):
#   make sign IDENTITY="Developer ID Application: Your Name (TEAMID)"
IDENTITY ?= -
sign: app
	codesign --force --deep --options runtime --sign "$(IDENTITY)" $(BUNDLE)
	codesign --verify --deep --strict --verbose=2 $(BUNDLE)

run: app
	open $(BUNDLE)

# Package the bundle into a distributable zip + checksum (the assets the curl
# installer downloads from a GitHub Release). ditto preserves the .app's
# structure and resource forks; zip does not.
release: app
	rm -f $(APP_NAME).zip $(APP_NAME).zip.sha256
	ditto -c -k --keepParent $(BUNDLE) $(APP_NAME).zip
	shasum -a 256 $(APP_NAME).zip | awk '{print $$1}' > $(APP_NAME).zip.sha256
	@echo "Built $(APP_NAME).zip ($$(cat $(APP_NAME).zip.sha256))"

clean:
	rm -rf .build $(BUNDLE) AppIcon.icns AppIcon.iconset \
		$(APP_NAME).zip $(APP_NAME).zip.sha256
