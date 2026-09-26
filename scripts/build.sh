#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${CREST_BUILD_DIR:-$ROOT/.build}"
DIST="${CREST_DIST_DIR:-$ROOT/dist}"
SDK="${CREST_SDK:-$(xcrun --show-sdk-path)}"
# Some CLT 27 installations omit SwiftUIMacros. Prefer the installed stable SDK.
if [[ -z "${CREST_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
CONFIG="${CREST_CONFIGURATION:-release}"
swift build --package-path "$ROOT" --scratch-path "$BUILD" --build-system native --sdk "$SDK" -c "$CONFIG"
BIN="$(swift build --package-path "$ROOT" --scratch-path "$BUILD" --build-system native --sdk "$SDK" -c "$CONFIG" --show-bin-path)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp/}crest-package.XXXXXX")"
APP="$STAGING/Crest.app"
mkdir -p "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/Crest" "$APP/Contents/MacOS/Crest"
cp "$BIN/crest-bridge" "$APP/Contents/Helpers/crest-bridge"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"; fi
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
