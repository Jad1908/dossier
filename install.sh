#!/bin/sh
# Dossier installer — installs the `dossier` CLI engine and the macOS app.
#
#   curl -fsSL https://raw.githubusercontent.com/Jad1908/dossier/main/install.sh | sh
#
# Installs:
#   1. the `dossier` command-line engine (via uv), and
#   2. Dossier.app from the latest GitHub Release (Apple Silicon).
set -eu

REPO="Jad1908/dossier"
APP="Dossier.app"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Dossier is macOS only."

# --- 1. The engine (dossier CLI) -------------------------------------------
# The app shells out to `dossier`; install it if it isn't already present.
if command -v dossier >/dev/null 2>&1; then
    say "dossier CLI already installed ($(command -v dossier))."
else
    if ! command -v uv >/dev/null 2>&1; then
        say "Installing uv (Python tool manager)…"
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    say "Installing the dossier CLI…"
    uv tool install --force "git+https://github.com/$REPO.git"
fi

# --- 2. The app -------------------------------------------------------------
if [ "$(uname -m)" != "arm64" ]; then
    warn "The prebuilt app is Apple Silicon only. On Intel, build from source:"
    warn "  git clone https://github.com/$REPO.git && cd dossier/app && make run"
    say "CLI installed. Skipping the app download on this architecture."
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
base="https://github.com/$REPO/releases/latest/download"

say "Downloading $APP…"
curl -fSL "$base/Dossier.zip" -o "$tmp/app.zip" \
    || die "Could not download the app. Has a release been published yet?"

# Verify the checksum when the release ships one.
if curl -fsSL "$base/Dossier.zip.sha256" -o "$tmp/sum" 2>/dev/null; then
    say "Verifying checksum…"
    ( cd "$tmp" && printf '%s  app.zip\n' "$(cat sum)" | shasum -a 256 -c - >/dev/null ) \
        || die "Checksum verification failed."
fi

ditto -x -k "$tmp/app.zip" "$tmp"
[ -d "$tmp/$APP" ] || die "Downloaded archive did not contain $APP."

dest="/Applications"
if [ -w "$dest" ] || [ "$(id -u)" = "0" ]; then :; else dest="$HOME/Applications"; fi
mkdir -p "$dest"
rm -rf "$dest/$APP"
mv "$tmp/$APP" "$dest/"

# The app is ad-hoc signed (not notarized); clear the download quarantine so it
# opens without the Gatekeeper prompt.
xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

say "Installed $dest/$APP"
open "$dest/$APP" 2>/dev/null || true
say "Done."
