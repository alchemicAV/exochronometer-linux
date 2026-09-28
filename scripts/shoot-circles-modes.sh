#!/usr/bin/env bash
# Capture the circles page in both modes, and the calendar's initial scroll.
#
# The mode is persisted (CirclesPage's @AppStorage), so the SELECTORS state can
# be captured deterministically by seeding the settings file instead of trying
# to synthesise a click. Section is rewritten, never regex-stripped.
set -u
CONF="$HOME/.config/QtProject/Qml Runtime.conf"
OUT=/tmp/shots
mkdir -p "$OUT"
cd "$HOME/exochronometer-linux/build/app" || exit 1

set_mode() {  # $1 = true|false
  python3 - "$1" <<'PY'
import sys
val = sys.argv[1]
path = __import__("os").path.expanduser("~/.config/QtProject/Qml Runtime.conf")
try:
    lines = open(path).read().splitlines()
except FileNotFoundError:
    lines = []
out, skip = [], False
for ln in lines:
    if ln.strip() == "[exochronometer-circles]":
        skip = True
        continue
    if skip and ln.startswith("["):
        skip = False
    if not skip:
        out.append(ln)
out.append("[exochronometer-circles]")
out.append(f"useSelectors={val}")
open(path, "w").write("\n".join(out) + "\n")
print(f"seeded useSelectors={val}")
PY
}

app_info() {
  python3 - <<'PY'
import json, subprocess
cl = json.loads(subprocess.run(["hyprctl","clients","-j"],capture_output=True).stdout)
act = json.loads(subprocess.run(["hyprctl","activewindow","-j"],capture_output=True).stdout)
for c in cl:
    if c.get("title") == "Exochronometer":
        x, y = c["at"]; w, h = c["size"]
        print(f"{x} {y} {w} {h} {'ACTIVE' if act.get('address')==c['address'] else 'INACTIVE'}")
        break
PY
}

capture() {  # $1=name
  local info
  info=$(app_info)
  set -- "$1" $info
  local name="$1"; local x="$2" y="$3" w="$4" h="$5" state="$6"
  if [ "$state" != "ACTIVE" ]; then echo "  $name SKIPPED (not active)"; return 1; fi
  grim -g "$x,$y ${w}x${h}" "$OUT/$name.png"
  echo "  $name -> $OUT/$name.png"
}

run_app() {
  qml6 main.qml >/dev/null 2>&1 &
  APP_PID=$!
  sleep 7
}

pkill -x qml6; sleep 1

echo "== CIRCLES mode =="
set_mode false
run_app
capture circles-mode
wtype -k 2; sleep 2.5          # page 2 = PEAK CALENDAR
capture calendar-scroll
kill $APP_PID 2>/dev/null; wait $APP_PID 2>/dev/null
sleep 1

echo "== SELECTORS mode =="
set_mode true
run_app
capture circles-selectors
kill $APP_PID 2>/dev/null; wait $APP_PID 2>/dev/null

echo "== restore default =="
set_mode false
echo done