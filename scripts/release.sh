#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/environment.sh"
: "${CREST_SIGN_IDENTITY:?Set the Developer ID Application signing identity}"
: "${CREST_NOTARY_PROFILE:?Set an existing notarytool Keychain profile name}"
: "${CREST_RELEASE_CONFIG:?Set a local release-config.json path}"
: "${CREST_DOWNLOAD_PREFIX:?Set HTTPS archive download prefix}"
[[ "$CREST_SIGN_IDENTITY" == "Developer ID Application:"* ]] || { echo 'A Developer ID Application identity is required'; exit 1; }
python3 - "$CREST_DOWNLOAD_PREFIX" <<'PY'
import sys
from urllib.parse import urlsplit
value = sys.argv[1]
url = urlsplit(value)
if (url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment
        or not value.endswith('/') or any(c.isspace() for c in value)):
    raise SystemExit('Download prefix must be HTTPS, without credentials/query/fragment, and end in /')
PY
bash "$ROOT/scripts/build.sh"
APP="$(cat "$DIST/app-path.txt")"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
# Sign Mach-O helpers first, then nested bundles, then the outer bundle.
while IFS= read -r -d '' executable; do
  if file "$executable" | grep -q 'Mach-O'; then codesign --force --options runtime --timestamp --sign "$CREST_SIGN_IDENTITY" "$executable"; fi
done < <(find "$FRAMEWORK" -type f -perm +111 -print0)
while IFS= read -r -d '' nested; do codesign --force --options runtime --timestamp --sign "$CREST_SIGN_IDENTITY" "$nested"; done < <(find "$FRAMEWORK" -depth -type d \( -name '*.xpc' -o -name '*.app' \) -print0)
codesign --force --options runtime --timestamp --sign "$CREST_SIGN_IDENTITY" "$FRAMEWORK"
codesign --force --options runtime --timestamp --sign "$CREST_SIGN_IDENTITY" "$APP/Contents/Helpers/crest-bridge"
codesign --force --options runtime --timestamp --entitlements "$ROOT/Resources/Crest.entitlements" --sign "$CREST_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$DIST/Crest-notarize.zip"
xcrun notarytool submit "$DIST/Crest-notarize.zip" --keychain-profile "$CREST_NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p "$DIST/updates"
ditto -c -k --keepParent "$APP" "$DIST/updates/Crest-$VERSION.zip"
TOOLS="$BUILD/artifacts/sparkle/Sparkle/bin"
FEED="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$APP/Contents/Info.plist")"
"$TOOLS/generate_appcast" --download-url-prefix "${CREST_DOWNLOAD_PREFIX:?Set HTTPS archive download prefix}" "$DIST/updates"
printf 'Release prepared locally. Upload archives and appcast to the locations referenced by %s\n' "$FEED"
