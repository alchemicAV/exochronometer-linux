#!/usr/bin/env bash
# Verify which audio engine the TOOLBAR (shell plugin) is actually running.
#
# The panel and the standalone app are separate copies of the same instrument, and
# the shell runs the plugin from ~/.config/omarchy/plugins/<id>/ - a COPY of the
# package, which drifts whenever the package is upgraded. A stale copy is invisible
# on screen: the shell happily runs an old plugin while the packaged one is current.
# That is how the panel spent a whole round on the pre-real-time buffer player,
# stopping on its own, while the app had already been fixed.
#
# So this checks three things, none of which is visible from the UI:
#   1. does the shell actually have the ExoAudio module mapped?
#   2. does the panel still match the installed package?
#   3. does the engine get constructed, and does it survive the panel closing?
set -uo pipefail

ID="alchemicav.exochronometer"
LIVE="$HOME/.config/omarchy/plugins/$ID"
TRACE=/tmp/exo-audio-life.log
SENTINEL=/tmp/exo-audio-trace

echo "--- 1. plugin copy vs package ---"
exochronometer-omarchy-plugin check || true

echo
echo "--- 2. restart the shell with tracing on ---"
touch "$SENTINEL"
rm -f "$TRACE"
rm -rf "$HOME/.cache/quickshell/qmlcache"
omarchy restart shell >/dev/null 2>&1
sleep 9

echo "engine construction at boot:"
cat "$TRACE" 2>/dev/null | sed 's/^/  /' || echo "  (no trace - engine not constructed)"

echo
echo "--- 3. open, then close, the panel ---"
omarchy-shell "$ID" toggle >/dev/null 2>&1; sleep 4
omarchy-shell "$ID" toggle >/dev/null 2>&1; sleep 4
echo "full lifecycle:"
cat -n "$TRACE" 2>/dev/null | sed 's/^/  /' || echo "  (no trace at all)"

echo
echo "--- 4. is the module mapped in the shell process? ---"
SP="$(pgrep -x quickshell | head -1)"
n="$(grep -c exoaudio "/proc/$SP/maps" 2>/dev/null || echo 0)"
if [ "$n" -gt 0 ]; then
  echo "  yes ($n mappings) - the panel is running the real-time engine"
else
  echo "  NO - the panel is NOT using the real-time module"
fi

echo
echo "--- 5. is the instrument the current one? ---"
if grep -q RealtimePlayer "$LIVE/HarmonicSpectrumPage.qml" 2>/dev/null; then
  echo "  yes: the panel's page loads RealtimePlayer.qml"
else
  echo "  NO: the panel's page has no RealtimePlayer - this copy predates real-time audio"
fi