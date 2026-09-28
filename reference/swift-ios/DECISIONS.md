# Exochronometer — Decision Log

The paper trail behind [THEORY.md](THEORY.md). Decisions are dated;
corrections of record stay here so errors don't silently vanish from the
project's history.

---

## 2026-06-09 — Theory tightening (first pass)

- **Star polygons (Q1).** The winding (visual) interpretation is canonical;
  the snapshot format already recorded (n/k)·f. k = 2 stars are exact
  octaves of their regular polygons, so aliasing them to integer harmonics
  is pitch-class exact.
- **Harmonics 3–8 (Q2)** is a legibility cap for the initial build, not a
  principled limit. Expansion deferred to a more mature stage.
- **Global synchrony (Q3)** affirmed as a core commitment: identical
  geometry everywhere on Earth at every instant. Year phase re-anchored to
  the December solstice (an observer-independent instant); day/hour/minute
  stay on UTC convention.
- **Fade fraction (Q4)** rationale recorded: tuned to taste within bounds —
  floor: the hour circle should hold ≈ 2 minutes of peak geometry
  (±10.8° ≈ ±108 s); ceiling: larger windows overlap badly at node
  clusters. Sensitivity analysis for its use as an *analysis* window
  remains open.

## 2026-06-09 — Re-anchoring (second pass, implemented)

- **Epoch → new moon.** `PhaseEpoch.instant` = 2014-12-22 01:36 UTC new
  moon; `PhaseEpoch.decemberSolstice` = 2014-12-21 23:03 UTC = year 0°.
  Moon 0° and year 0° coincide to within 2.5 h (Metonic "meeting of sun
  and moon"; recurs 1995 → 2014 → 2033). A full-moon epoch was considered
  and rejected: moon-phase math defines 0° = new moon, and the best
  solstice full moon (June 2016) is ~5× looser (≈ 11.5 h).
- **Year = mean tropical year** (365.24219 d) everywhere — frequency,
  phase, and duration formatting — replacing both the fixed 365.25-d
  frequency and the civil-calendar phase. Jan 1 now sits ≈ 10.2° into the
  year cycle.
- **k = 3 winding tones sound.** {7/3} and {8/3} are distinct tones at
  (n/k)·f with winding-aware activation (duty 6%·n/k, firing on 1-in-k
  rotations per vertex; amplitude equals the regular polygon's at visit
  moments). Verified by simulation: frequency ratios exact, pitch classes
  266.87¢ and 498.04¢, exit times winding-aware. All layers (visual /
  tonal / snapshot / chords / audio / Lissajous) agree.
- **Stale journal data → purge, not migrate.** Pre-release notes recorded
  under the old anchors are deleted at app launch
  (`JournalNote.purgeStaleSchema`; snapshot schema bumped to v2).

## 2026-06-10 — Chord layer

- **Within-family chords stay — commensurate-family filter rejected.**
  The winding tones exposed that every interval within a commensurate
  family is exact for all time (MN:7/3 ↔ QM:7 is a 0.0¢ perfect fifth by
  construction). A filter requiring chords to span ≥ 2 families
  (civil / lunar / solar) was implemented and rejected by the author the
  same day: life runs on the day–week–month lattice, so recurring
  within-family chords are experientially relevant — repetition is not
  irrelevance. `crossTimeframeOnly` keeps its original meaning (≥ 2
  distinct timeframes).
- **Winding gating verified end-to-end** after a false alarm (the
  author's own calculation error, gracefully retracted): tones fire on
  1-in-3 vertex passes (13.9% duty on the moon), never sound without
  their parent polygon lit, and all 63 winding-involving events in a
  30-day projection had their stars genuinely active at event peak.
  Two legitimate perception gaps noted: *upcoming* projections list
  future events whose stars are not yet visible (by design), and near
  the 0.3 amplitude threshold a star renders at ~0.3 opacity legs /
  ~0.1 baseline — active but easy to miss.
- **"Open Fifth + 8va" (5+8) cut from the chord vocabulary.** Only two
  distinct pitch classes — an interval in chord costume — and the exact
  winding fifth left it one drifting day-tone from firing ~5×/day.
  Establishes the rule: **a chord requires ≥ 3 distinct pitch classes.**
  The `intervals` vocabulary is untouched. Result: sus2/sus4 chords became
  visible in the convergence list for the first time.
- **Year-circle node labels fixed** (iOS + Mac): they still computed the
  cycle start from civil Jan 1 after the solstice re-anchor.

## 2026-06-14 — Trigger clip rendering (design, not yet built)

Goal: a 5–10 s video clip auto-captured at every trigger (chord onset
first), showing the **whole canvas** — not just the on-screen viewport —
and working in **headless** mode. Latency tolerance: 20–30 s after the
fire; faster is better.

- **Don't record — re-derive.** The canvas is a pure function of
  `snapshotDate` (the snapshot path already renders any instant offscreen
  via `StaticCanvas` + `captureBounds` + `exoCaptureMode`). So a trigger
  clip needs no running recorder and no pre-roll ring buffer: on a fire at
  `t`, render the window `[t−pre, t+post]` offscreen, frame by frame,
  faster than real time. This is what makes "clip at *every* trigger"
  cheap rather than expensive.
- **Consequences, all for free:** whole canvas (it's the full
  `captureBounds`, off-view widgets included); headless (no window needed);
  **pre-roll is free** (the past is as renderable as the future — for a
  chord onset you want the build-*up* into the chord, e.g. `[t−3s, t+7s]`);
  faster-than-real-time render fits the latency budget with room to spare.
- **The render can run *ahead* of the moment.** Trigger times are
  themselves date math (geometry peaks, phase closures, chord onsets are
  all predictable). So upcoming clips can be **pre-rendered before they
  occur** — ready (or post-queued) at `t` with *zero* latency. The render
  is not bound to wall-clock; it can lead it.
- **Audio gets *easier*, not harder.** Amplitudes are also a pure function
  of date (`HarmonicAnalysis.activeTones(at:)`). Render audio offline
  through `AVAudioEngine`'s **manual rendering mode** (runs the real graph —
  reverb, voicing — faster than real time), driven from `activeTones` on
  the same date timeline as the video → **A/V sync by construction**.
  Cheap fallback if deferred: silent clips.
- **Costs to watch.** `ImageRenderer` per-frame (`@MainActor`, re-evaluates
  the board each frame, ~50–200 ms/frame on a big board) is the bottleneck,
  not storage — cap fps/scale for *auto* clips (15–24 fps, 1×) to stay
  inside budget. Storage ≈ 0.5–2 MB per clip (line-art on black); add a
  retention policy (keep last N / N days) + per-trigger bitrate caps;
  cooldowns already throttle frequency.
- **Determinism caveat.** Verify per widget that the offscreen render
  reconstructs from the date window. The **spectrogram** is the one to
  check — fine if its rolling history is computed from a date range (as the
  still snapshot already does), broken if it accumulates live samples.
- **Shape.** A `ClipRenderer(triggerDate, pre, post, fps, scale)` emitting
  one `.mp4` as a trigger artifact alongside the existing `.png`, reusing
  `captureBounds` / `StaticCanvas` / `exoCaptureMode` / the `AVAssetWriter`
  settings. New code = frame loop + `AVAssetWriterInputPixelBufferAdaptor`
  + the manual-render audio bridge. The existing ScreenCaptureKit recorder
  stays as the "record my live screen (cursor, knob-twiddling)" path; this
  is the "render any moment, whole board, headless" path.

---

## Corrections of record

- An early theory conversation claimed all five fundamentals are mutually
  incommensurate. **False for the civil units**: day:hour = 24 and
  hour:minute = 60 exactly, forming the exact C–G–F♯ chord (THEORY.md §3).
  Only the year and moon are incommensurate with the rest.
- The 432 Hz digit-sum (mod 9) property is real arithmetic
  (432 = 2⁴ · 3³; powers of 10 ≡ 1 mod 9) but is a property of base-10
  notation, not of sound. The anchor is decorative: every metric in the
  system is interval-relative.

---

## Open items

- **Recalibrate the meters.** `DissonanceCalibration` constants predate
  the winding tones and tropical year. Run the Mac Calibration menu
  (⌘⇧K) and update `tenneyMeterMax` / `entropyMeterMax`.
- **Episode dedup (watch item).** If identical-signature triad repeats
  during lunar windows prove noisy in posts, dedup at the posting layer:
  same pitch-class signature re-onsetting while its slowest tone stays
  continuously active = one episode.
- **Sensitivity analysis (Q5).** Sweep fadeFraction, σ, and the JI list in
  the year simulation; moments that exist only at σ = 30 are artifacts of
  σ = 30.
- **Cross-cycle phase identity (Q-cross-cycle).** Is 120° on the year
  related to 120° on the day? Not an octave (cycles are not 2:1); an
  empirical question for conjecture C2's cross-timeframe term.
- **Conjecture experiments C1–C3** (THEORY.md §10): preregistered windows,
  sham controls, embeddings over timestamped text.
