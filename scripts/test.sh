#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/environment.sh"
swift run --package-path "$PACKAGE" --scratch-path "$BUILD" --build-system native --sdk "$SDK" CrestChecks
swift build --package-path "$PACKAGE" --scratch-path "$BUILD" --build-system native --sdk "$SDK" --product crest-bridge
BIN="$(swift build --package-path "$PACKAGE" --scratch-path "$BUILD" --build-system native --sdk "$SDK" --show-bin-path)"
python3 "$ROOT/scripts/test-bridge.py" "$BIN/crest-bridge"

python3 "$ROOT/scripts/test-release.py"
