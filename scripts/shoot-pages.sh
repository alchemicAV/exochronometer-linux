#!/usr/bin/env bash
# Screenshot the app's pages, verifying each capture really is the app.
#
# Two traps this guards against, both of which produced convincing but WRONG
# verification images earlier:
#   * grim -g takes logical coordinates but writes PHYSICAL pixels, so on a
#     1.5x-scaled monitor a 621x670 request yields a 931x1005 PNG. Cropping or
#     measuring that image with logical coordinates reads the wrong area.
#   * if the app is not the focused/raised window, grim happily captures
#     whatever else occupies that rectangle (here: the editor window), and the
#     geometry being correct makes the result look trustworthy.
# So: assert the app is the active window before every capture, and record the
# real pixel size of each PNG.
set -u
APP_DIR="$HOME/exochronometer-linux/build/app"
OUT=/tmp/shots
mkdir -p "$OUT"
cd "$APP_DIR" || exit 1

qml6 main.qml >/dev/null 2>&1 &
QLMPID=$!
sleep 7

app_info() {
  python3 - <<'PY'
import json, subprocess
cl = json.loads(subprocess.run(["hyprctl","clients","-j"],capture_output=True).stdout)
act = json.loads(subprocess.run(["hyprctl","activewindow","-j"],capture_output=True).stdout)
me = None
for c in cl:
    if c.get("title") == "Exochronometer":
        me = c
        break
if not me:
    print("MISSING"); raise SystemExit
x, y = me["at"]; w, h = me["size"]
active = act.get("address") == me["address"]
print(f"{x} {y} {w} {h} {'ACTIVE' if active else 'INACTIVE'}")
PY
}

shot() {  # $1=key $2=name
  local info x y w h state
  info=$(app_info)
  set -- "$1" "$2" $info
  local key="$1" name="$2"; x="$3"; y="$4"; w="$5"; h="$6"; state="$7"
  if [ "$state" != "ACTIVE" ]; then
    echo "  $name SKIPPED - app window is not active (would capture the wrong window)"
    return 1
  fi
  wtype -k "$key" 2>/dev/null || wtype "$key"
  sleep 2
  grim -g "$x,$y ${w}x${h}" "$OUT/$name.png"
  echo "  $name -> $OUT/$name.png  $(file -b "$OUT/$name.png" | cut -d, -f2 | tr -d ' ')"
}

shot 1 circles
shot 2 calendar
shot 3 geometry
shot 4 misc-phase
shot 5 timeline
shot 6 spectrum

kill $QLMPID 2>/dev/null
wait $QLMPID 2>/dev/null
echo done