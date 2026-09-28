#!/usr/bin/env bash
# Run the whole numeric validation suite against the Swift-generated vectors.
#
# The two TZ-dependent vector sets MUST run under their matching timezone or the
# comparison produces false failures.
set -u
cd "$HOME/exochronometer-linux" || exit 1

pass=0; fail=0; skipped=0
run() {  # $1=label $2=tz $3=script $4=vectors
  local out
  out=$(TZ="$2" node "$3" "$4" 2>&1)
  if [ $? -eq 0 ]; then
    pass=$((pass+1))
    printf 'PASS  %-34s %s\n' "$1" "$(echo "$out" | tail -1)"
  else
    fail=$((fail+1))
    printf 'FAIL  %-34s\n' "$1"
    echo "$out" | tail -6 | sed 's/^/        /'
  fi
}

# No vectors file to pass.
run0() {  # $1=label $2=script
  local out
  out=$(node "$2" 2>&1)
  local rc=$?
  # 77 is a deliberate skip: the check needs hardware this machine may not have
  # (an audio output, a display). Reporting a skip as a pass would be a lie.
  if [ "$rc" -eq 77 ]; then
    skipped=$((skipped+1))
    printf 'SKIP  %-34s %s\n' "$1" "$(echo "$out" | tail -1)"
    return
  fi
  if [ "$rc" -eq 0 ]; then
    pass=$((pass+1))
    printf 'PASS  %-34s %s\n' "$1" "$(echo "$out" | tail -1)"
  else
    fail=$((fail+1))
    printf 'FAIL  %-34s\n' "$1"
    echo "$out" | tail -6 | sed 's/^/        /'
  fi
}

run "foundation (UTC)"        UTC                 test/validate.mjs            reference/vectors-utc.json
run "foundation (New York)"   America/New_York    test/validate.mjs            reference/vectors-ny.json
run "node labels (UTC)"       UTC                 test/validate-nodelabels.mjs reference/vectors-nodelabels-utc.json
run "node labels (New York)"  America/New_York    test/validate-nodelabels.mjs reference/vectors-nodelabels-ny.json
run "peak calendar"           UTC                 test/validate-calendar.mjs   reference/vectors-calendar.json
run "peak calendar (New York)" America/New_York   test/validate-calendar.mjs   reference/vectors-calendar-ny.json
run "dissonance"              UTC                 test/validate-dissonance.mjs reference/vectors-dissonance.json
run "harmonic analysis"       UTC                 test/validate-analysis.mjs   reference/vectors-analysis.json
run "chord projector"         UTC                 test/validate-chords.mjs     reference/vectors-chords.json
run "frequency / printfFixed" UTC                 test/validate-freq.mjs       reference/vectors-freq.json
run "harmonic colour"           UTC                 test/validate-color.mjs      reference/vectors-color.json

# The WAV renderer takes no vectors: the Swift original played through
# AVFoundation, which exports no numbers. Its validator checks the samples
# against an independent evaluation of the same sum instead.
run0 "wav renderer"                                 test/validate-wav.mjs

# The real-time C++ kernel has no Swift oracle either (AVFoundation exported no
# numbers), so it is checked against the JS kernel it must agree with. This builds
# the module on first run if it is not there yet.
run0 "realtime kernel (C++ vs JS)"                  test/validate-realtime.mjs

# What the SOUND DEVICE is actually fed. This is the only check that would have
# caught the format bug that made the first real-time build sound choppy - the
# kernel checks, the envelope reproduction and every on-screen counter were all
# clean while the device was being fed half-rate data. Needs an audio output and a
# display, so it skips where those are absent.
run0 "device audio (no dropouts)"                   test/validate-device-audio.mjs

echo
echo "$pass passed, $fail failed, $skipped skipped"
[ "$fail" -eq 0 ]