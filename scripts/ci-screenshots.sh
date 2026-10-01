#!/bin/bash
# CI only. `ci-screenshots.sh APP` launches the packaged app in preview states and saves JPEG
# captures to $RUNNER_TEMP/crest-screens, writing fixture data into the runner's throwaway home.
# `ci-screenshots.sh emit NAME` posts one capture as chunked notice annotations, which can be read
# through the check-run API when artifact downloads are unavailable (at most 10 per step).
set -uo pipefail
[[ -n "${CI:-}" ]] || { echo 'Refusing to run outside CI: this replaces Crest preferences and data.'; exit 1; }
OUT="${RUNNER_TEMP:-/tmp}/crest-screens"; mkdir -p "$OUT"
if [[ "${1:-}" == emit ]]; then
  for name in "${@:2}"; do
    [[ -s "$OUT/$name.jpg" ]] || { echo "No capture for $name"; continue; }
    data="$(base64 -i "$OUT/$name.jpg" | tr -d '\n')"; count=$(( (${#data} + 4095) / 4096 ))
    for ((i = 0; i < count; i++)); do echo "::notice title=shot-$name-$i-$count::${data:i*4096:4096}"; done
  done
  exit 0
fi
APP="$1/Contents/MacOS/Crest"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="$HOME/Library/Application Support/Crest"; mkdir -p "$DATA"
DOMAIN=app.crest.mac
WIDTH="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); $.NSScreen.mainScreen.frame.size.width' 2>/dev/null || echo 1440)"
X=$(( ${WIDTH%.*} / 2 - 300 ))
echo "Screen width $WIDTH; capturing from x=$X"
# capture NAME HEIGHT [app arguments...]; a function named during_NAME runs while the app is open.
capture() {
  local name="$1" height="$2"; shift 2
  rm -f "$OUT/$name.png" "$OUT/$name.jpg"
  "$APP" --smoke-test "$@" &
  local pid=$!
  if declare -F "during_$name" >/dev/null; then "during_$name"; else sleep 2; fi
  screencapture -x -R"$X,0,600,$height" "$OUT/$name.png" 2>/dev/null
  wait "$pid"; local status=$?
  [[ $status -eq 0 ]] || echo "::warning title=launch-$name::exit status $status"
  [[ -s "$OUT/$name.png" ]] || { echo "::warning title=capture-$name::no image"; return 0; }
  local quality
  for quality in 60 50 40 30 22; do
    sips -s format jpeg -s formatOptions "$quality" --resampleWidth 560 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null 2>&1
    sips -d profile "$OUT/$name.jpg" >/dev/null 2>&1
    (( $(wc -c < "$OUT/$name.jpg") <= 29000 )) && break
  done
  echo "$name: $(wc -c < "$OUT/$name.jpg") bytes at quality $quality"
}
during_hud() { sleep 1.2; osascript -e 'set volume output volume 30' >/dev/null 2>&1; sleep 0.6; }

defaults write "$DOMAIN" onboarded -bool false
capture welcome 560

defaults write "$DOMAIN" onboarded -bool true
python3 - "$DATA/tray.json" "$ROOT" "$OUT/welcome.png" <<'PY'
import json, sys, time, uuid
target, root, image = sys.argv[1:4]
paths = [image, f"{root}/Resources/AppIcon.icns", f"{root}/README.md", f"{root}/docs"]
reference = time.time() - 978307200
json.dump([{"id": str(uuid.uuid4()).upper(), "path": p, "date": reference} for p in paths], open(target, "w"))
PY
printf 'Ship 0.4 notes\n- Live activities beside the notch\n- Focus timer and keep awake\n- Check the tray thumbnails\n' > "$DATA/notes.txt"
for tab in Overview Agents Tray Clipboard Notes; do capture "$tab" 560 --preview "$tab"; done

# A running focus timer: the collapsed live activity and the active Overview card.
HEX="$(python3 -c 'import json,time; print(json.dumps({"duration":1500,"endsAt":time.time()+1400-978307200}).encode().hex())')"
defaults write "$DOMAIN" focusTimer -data "$HEX"
capture timer-collapsed 80 --preview collapsed
capture timer-overview 560 --preview Overview
defaults delete "$DOMAIN" focusTimer
capture hud 80 --preview collapsed
exit 0
