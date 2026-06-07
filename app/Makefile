# Build Dossier.app from the Swift package.
#
# `swift build` produces a plain executable; macOS needs a .app bundle (with an
# Info.plist) to run it as a real windowed app with a Dock icon and menu bar.
# `make app` builds release and assembles that bundle.

APP_NAME = Dossier
BUNDLE   = $(APP_NAME).app
CONFIG   = release
BIN      = .build/$(CONFIG)/$(APP_NAME)

.PHONY: all app build run clean

all: app

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	mkdir -p $(BUNDLE)/Contents/Resources
	cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(BUNDLE)/Contents/Info.plist
	@echo "Built $(BUNDLE)"

run: app
	open $(BUNDLE)

clean:
	rm -rf .build $(BUNDLE)
