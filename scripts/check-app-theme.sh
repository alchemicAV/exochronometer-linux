#!/usr/bin/env bash
# Launch the app with a theme palette and measure the window background, to show
# the palette actually reached the app rather than the fallback.
set -u
cd "$HOME/exochronometer-linux/build/app" || exit 1

TD="$HOME/.local/state/omarchy/current/theme/colors.toml"
val() { grep -m1 -E "^[[:space:]]*$1[[:space:]]*=" "$TD" | sed 's/.*=//' | tr -d ' \t"'; }

qml6 main.qml \
  --theme-bg "$(val background)" \
  --theme-fg "$(val foreground)" \
  --theme-accent "$(val accent)" \
  --theme-muted "$(val muted)" \
  --theme-urgent "$(val red)" \
  --theme-surface "$(val lighter_background)" &
APP_PID=$!
sleep 8

GEO=$(hyprctl clients -j | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    if c.get('title') == 'Exochronometer':
        x,y = c['at']; w,h = c['size']
        print(f'{x},{y} {w}x{h}')
        break
")
if [ -z "$GEO" ]; then echo "  window not found"; kill $APP_PID 2>/dev/null; exit 1; fi
echo "  window: $GEO"

grim -g "$GEO" /tmp/app-themed.png
python3 - "$(val background)" <<'PY'
import sys
from PIL import Image
want = sys.argv[1].lstrip('#')
want_rgb = tuple(int(want[i:i+2], 16) for i in (0, 2, 4))
im = Image.open('/tmp/app-themed.png').convert('RGB'); px = im.load()
pts = [px[im.width-8, im.height//2], px[im.width//2, im.height-8], px[8, im.height//2]]
print(f"  theme background  : {want_rgb}")
print(f"  app samples       : {pts}")
print("  => MATCH" if any(abs(s[0]-want_rgb[0]) < 12 and abs(s[1]-want_rgb[1]) < 12 for s in pts)
      else "  => the app is NOT using the theme background")
PY
kill $APP_PID 2>/dev/null