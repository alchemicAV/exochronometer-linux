#!/usr/bin/env bash
# Capture what the sound device is actually being fed while the instrument plays.
#
# The synthesis measured clean in isolation, so the question is what the DEVICE
# receives. Recording the sink's monitor is the only way to see that - and unlike
# my internal counters it includes any resampling, gaps or stalls the audio stack
# introduces on the way out.
set -uo pipefail

REPO="$HOME/exochronometer-linux"
OUT="${1:-/tmp/mon.wav}"
SECONDS_TO_RECORD="${2:-10}"
SINK="$(pactl get-default-sink)"
MON="$SINK.monitor"

echo "sink   : $SINK"
echo "monitor: $MON"

# Play through the app's own code path, then give it a moment to settle.
( cd "$REPO" && timeout 22 python3 scripts/shoot-states.py spectrum-rt >/tmp/capture-harness.log 2>&1 & )
sleep 4

echo "recording ${SECONDS_TO_RECORD}s -> $OUT"
timeout $((SECONDS_TO_RECORD + 4)) parec -d "$MON" --rate=48000 --channels=2 \
    --format=s16le --file-format=wav "$OUT" >/dev/null 2>&1
echo "recorded: $(stat -c%s "$OUT" 2>/dev/null || echo 0) bytes"