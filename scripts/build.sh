#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/environment.sh"
CONFIG="${CREST_CONFIGURATION:-release}"
swift build --package-path "$PACKAGE" --scratch-path "$BUILD" --build-system native --sdk "$SDK" -c "$CONFIG"
BIN="$(swift build --package-path "$PACKAGE" --scratch-path "$BUILD" --build-system native --sdk "$SDK" -c "$CONFIG" --show-bin-path)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp/}crest-package.XXXXXX")"
APP="$STAGING/Crest.app"
mkdir -p "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Crest" "$APP/Contents/MacOS/Crest"
cp "$BIN/crest-bridge" "$APP/Contents/Helpers/crest-bridge"
cp "$PACKAGE/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$PACKAGE/Resources/AppIcon.icns" ]]; then cp "$PACKAGE/Resources/AppIcon.icns" "$APP/Contents/Resources/"; fi
SPARKLE="$BUILD/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "${CREST_RELEASE_CONFIG:-}" ]]; then
  python3 "$ROOT/scripts/configure-release.py" "$CREST_RELEASE_CONFIG" "$APP/Contents/Info.plist"
fi
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
# Local development only. Release signing is a separate, fail-closed step.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$DIST/Crest.zip"
printf '%s\n' "$APP" > "$DIST/app-path.txt"
printf 'Built and verified %s\nPackaged %s/Crest.zip\n' "$APP" "$DIST"
