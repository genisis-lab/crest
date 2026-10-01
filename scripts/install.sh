#!/bin/bash
# Install Crest into /Applications (or ~/Applications) and open it.
#   bash scripts/install.sh               build from this checkout, then install
#   bash scripts/install.sh PATH          install from Crest.zip, a downloaded CI artifact (zip or
#                                         unzipped folder), or a Crest.app
# Set CREST_INSTALL_DIR to choose another folder, CREST_NO_LAUNCH=1 to skip opening.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'Crest installs on macOS only.'; exit 1; }
SOURCE="${1:-}"
if [[ -z "$SOURCE" ]]; then
  bash "$ROOT/scripts/build.sh"
  SOURCE="${CREST_DIST_DIR:-$ROOT/dist}/Crest.zip"
fi
SOURCE="${SOURCE%/}"
[[ -e "$SOURCE" ]] || { echo "Not found: $SOURCE"; exit 1; }
STAGING="$(mktemp -d "${TMPDIR:-/tmp/}crest-install.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

# Finds Crest.app in a folder, unpacking a nested Crest.zip (as in a CI artifact) after its checksum passes.
find_app() {
  local found target
  found="$(find "$1" -maxdepth 2 -name Crest.app -type d -prune | head -n 1)"
  if [[ -n "$found" ]]; then printf '%s\n' "$found"; return 0; fi
  found="$(find "$1" -maxdepth 3 -name Crest.zip -type f | head -n 1)"
  [[ -n "$found" ]] || return 1
  if [[ -f "$(dirname "$found")/Crest.sha256" ]]; then
    (cd "$(dirname "$found")" && shasum -a 256 -c Crest.sha256 >/dev/null) || { echo 'Crest.zip does not match Crest.sha256.' >&2; return 1; }
  fi
  target="$(mktemp -d "$STAGING/inner.XXXXXX")"
  ditto -x -k "$found" "$target"
  find "$target" -maxdepth 2 -name Crest.app -type d -prune | head -n 1
}
APP=""
if [[ -d "$SOURCE" && "$SOURCE" == *.app ]]; then APP="$SOURCE"
elif [[ -d "$SOURCE" ]]; then APP="$(find_app "$SOURCE")" || true
else ditto -x -k "$SOURCE" "$STAGING/outer"; APP="$(find_app "$STAGING/outer")" || true
fi
[[ -n "$APP" && -d "$APP" ]] || { echo 'No Crest.app found to install.'; exit 1; }
codesign --verify --deep --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")" == app.crest.mac ]] || { echo 'Unexpected bundle identifier.'; exit 1; }

DEST="${CREST_INSTALL_DIR:-/Applications}"
if [[ ! -w "$DEST" ]]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
TARGET="$DEST/Crest.app"
if [[ -e "$TARGET" ]]; then
  # Only ever replace an existing Crest; anything else at that path is left alone.
  EXISTING="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$TARGET/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$EXISTING" == app.crest.mac ]] || { echo "$TARGET exists and is not Crest. Move it first."; exit 1; }
fi
if pgrep -x Crest >/dev/null; then
  osascript -e 'quit app id "app.crest.mac"' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Crest >/dev/null || break; sleep 0.5; done
  pkill -x Crest 2>/dev/null || true
fi
rm -rf "$TARGET"
ditto "$APP" "$TARGET"
# Ad-hoc signed development build: clear the download quarantine so Gatekeeper opens it.
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TARGET/Contents/Info.plist")"
printf 'Installed Crest %s at %s\n' "$VERSION" "$TARGET"
if [[ -z "${CREST_NO_LAUNCH:-}" ]]; then open "$TARGET"; fi
