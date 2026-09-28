#!/usr/bin/env bash
# Record the default sink's monitor while an arbitrary command runs.
#
# Usage: capture-while.sh <out.wav> <seconds> <command...>
set -uo pipefail

OUT="$1"; shift
SECS="$1"; shift

MON="$(pactl get-default-sink).monitor"

"$@" >/tmp/capture-while.log 2>&1 &
CMD=$!
sleep 2.5                                    # let the client start playing
timeout $((SECS + 3)) parec -d "$MON" --rate=48000 --channels=2 \
    --format=s16le --file-format=wav "$OUT" >/dev/null 2>&1
wait $CMD 2>/dev/null
echo "$OUT: $(stat -c%s "$OUT" 2>/dev/null || echo 0) bytes"