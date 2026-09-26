#!/bin/bash
# Keep compiler intermediates out of iCloud/File Provider managed source folders.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_TAG="$(printf '%s' "$ROOT" | /usr/bin/shasum -a 256 | /usr/bin/cut -c 1-12)"
BUILD="${CREST_BUILD_DIR:-$HOME/Library/Caches/Crest/build-$CACHE_TAG}"
PACKAGE="$BUILD/source-snapshot"
DIST="${CREST_DIST_DIR:-$ROOT/dist}"
SDK="${CREST_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${CREST_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
# File Provider can also change source timestamps during compilation. Compile a
# content-identical local snapshot; delete only obsolete files in this generated copy.
mkdir -p "$PACKAGE"
for directory in Sources Tests Resources; do
  mkdir -p "$PACKAGE/$directory"
  /usr/bin/rsync -a --checksum --delete "$ROOT/$directory/" "$PACKAGE/$directory/"
done
cp "$ROOT/Package.swift" "$PACKAGE/Package.swift"
if [[ -f "$ROOT/Package.resolved" ]]; then cp "$ROOT/Package.resolved" "$PACKAGE/Package.resolved"; fi
