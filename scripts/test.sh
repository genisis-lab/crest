#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${CREST_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${CREST_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
swift run --package-path "$ROOT" --scratch-path "${CREST_BUILD_DIR:-$ROOT/.build}" --build-system native --sdk "$SDK" CrestChecks
swift build --package-path "$ROOT" --scratch-path "${CREST_BUILD_DIR:-$ROOT/.build}" --build-system native --sdk "$SDK" --product crest-bridge
BIN="$(swift build --package-path "$ROOT" --scratch-path "${CREST_BUILD_DIR:-$ROOT/.build}" --build-system native --sdk "$SDK" --show-bin-path)"
python3 "$ROOT/scripts/test-bridge.py" "$BIN/crest-bridge"
