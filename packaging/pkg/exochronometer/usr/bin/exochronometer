#!/bin/bash
# Launcher for the Exochronometer QML app.
#
# Reads the current Omarchy theme and hands the palette to the app as command
# line arguments: QML cannot read files in this build (XMLHttpRequest returns an
# empty response for file:// URLs - verified), but it CAN read
# Qt.application.arguments. Without a theme the app falls back to the deliberate
# defaults in Theme.qml, so this stays optional.
set -u

THEME_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme"

toml_value() {  # $1 = file, $2 = key -> value with quotes and spaces stripped
  local line
  [ -r "$1" ] || return 0
  line=$(grep -m1 -E "^[[:space:]]*$2[[:space:]]*=" "$1" 2>/dev/null) || return 0
  printf '%s' "${line#*=}" | tr -d ' \t"'
}

args=()
add() {  # $1 = file, $2 = key, $3 = flag
  local v
  v=$(toml_value "$1" "$2")
  [ -n "$v" ] && args+=("$3" "$v")
}

COLORS="$THEME_DIR/colors.toml"
add "$COLORS" background          --theme-bg
add "$COLORS" dark_background     --theme-bg-dark
add "$COLORS" lighter_background  --theme-surface
add "$COLORS" foreground          --theme-fg
add "$COLORS" muted               --theme-muted
add "$COLORS" accent              --theme-accent
add "$COLORS" red                 --theme-urgent
# Text drawn on an accent-filled chip reads best as the background colour.
add "$COLORS" background          --theme-on-accent

exec qml6 /usr/share/exochronometer/main.qml "${args[@]}" "$@"