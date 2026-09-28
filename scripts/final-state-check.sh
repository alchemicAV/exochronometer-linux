#!/usr/bin/env bash
# Final state check: are both hosts actually running the current, fixed build?
set -uo pipefail
cd "$HOME/exochronometer-linux"

echo "=== the shell's plugin copy is current? ==="
exochronometer-omarchy-plugin check

echo
echo "=== is the shell running the real-time engine? ==="
SP="$(pgrep -x quickshell | head -1)"
LIVE="$HOME/.config/omarchy/plugins/alchemicav.exochronometer"
echo "  shell pid: $SP"
echo "  ExoAudio mappings in the shell: $(grep -c exoaudio "/proc/$SP/maps" 2>/dev/null || echo 0)"
echo "  panel page loads RealtimePlayer: $(grep -c RealtimePlayer "$LIVE/HarmonicSpectrumPage.qml" 2>/dev/null || echo 0)"

echo
echo "=== packages ==="
pacman -Q exochronometer exochronometer-omarchy

echo
echo "=== validator suite ==="
bash scripts/run-validators.sh 2>&1 | tail -3