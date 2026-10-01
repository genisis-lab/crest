#!/bin/bash
# CI only: launch the packaged app in preview states, capture the panel, and emit each capture as a
# notice annotation (base64 JPEG), readable through the check-run annotations API when artifact
# storage is unavailable. Writes fixture data into the runner's throwaway home folder.
set -uo pipefail
[[ -n "${CI:-}" ]] || { echo 'Refusing to run outside CI: this replaces Crest preferences and data.'; exit 1; }
APP="$1/Contents/MacOS/Crest"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${RUNNER_TEMP:-/tmp}/crest-screens"; mkdir -p "$OUT"
DATA="$HOME/Library/Application Support/Crest"; mkdir -p "$DATA"
DOMAIN=app.crest.mac
WIDTH="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.mainScreen.frame.size.width' 2>/dev/null || echo 1440)"
X=$(( ${WIDTH%.*} / 2 - 300 ))
echo "Screen width $WIDTH; capturing x=$X"
capture() {
  local name="$1"; shift
  rm -f "$OUT/$name.png" "$OUT/$name.jpg"
  "$APP" --smoke-test "$@" &
  local pid=$!
  sleep 2
  screencapture -x -R"$X,0,600,560" "$OUT/$name.png" 2>/dev/null
  wait "$pid"; local status=$?
  [[ $status -eq 0 ]] || echo "::warning title=launch-$name::exit status $status"
  [[ -s "$OUT/$name.png" ]] || { echo "::warning title=capture-$name::no image"; return 0; }
  sips -s format jpeg -s formatOptions 50 --resampleWidth 560 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null
  echo "$name: $(wc -c < "$OUT/$name.jpg") bytes"
  echo "::notice title=screenshot-$name::$(base64 -i "$OUT/$name.jpg" | tr -d '\n')"
}

defaults write "$DOMAIN" onboarded -bool false
capture welcome

defaults write "$DOMAIN" onboarded -bool true
python3 - "$DATA/tray.json" "$ROOT" "$OUT/welcome.png" <<'PY'
import json, sys, time, uuid
target, root, image = sys.argv[1:4]
paths = [image, f"{root}/Resources/AppIcon.icns", f"{root}/README.md", f"{root}/docs"]
reference = time.time() - 978307200
json.dump([{"id": str(uuid.uuid4()).upper(), "path": p, "date": reference} for p in paths], open(target, "w"))
PY
printf 'Ship 0.4 notes\n- Live activities beside the notch\n- Focus timer and keep awake\n- Check the tray thumbnails\n' > "$DATA/notes.txt"
for tab in Overview Agents Tray Clipboard Notes; do capture "$tab" --preview "$tab"; done

# A running focus timer: the collapsed live activity and the active Overview card.
HEX="$(python3 -c 'import json,time; print(json.dumps({"duration":1500,"endsAt":time.time()+1400-978307200}).encode().hex())')"
defaults write "$DOMAIN" focusTimer -data "$HEX"
capture timer-collapsed --preview collapsed
capture timer-overview --preview Overview
exit 0
