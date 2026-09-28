# Exochronometer

Native SwiftUI implementation of [exochronometer](https://github.com/alchemicAV/exochronometer) —
nested cycles of time (year, moon, quarter moon, day, hour, minute) rendered
as circles, inscribed geometry, and a slowly evolving just-intonation chord.

- **[THEORY.md](THEORY.md)** — the theory: cycles as tones, geometry as
  harmonics, the fixed civil chord, the grand zero, the conjectures.
- **[WIDGETS.md](WIDGETS.md)** — the instrument panel: every widget with its
  math and how to read it.
- **[DECISIONS.md](DECISIONS.md)** — dated decision log, corrections of
  record, and open items.

## Targets

### Exochronometer (iOS app)
- **Circles** — the six time circles with breathing {n/k} polygon overlays,
  journal note markers, and node date labels.
- **Timeline** — vertical journal/snapshot history.
- **Geometry Harmonics** — reference view of every shape's period,
  frequency, and nearest JI note.
- **Harmonic Analysis** — live spectrum of sounding tones (per-timeframe
  octave lifts, waxing/waning states) with sine-bank audio.
- **Spatial Analysis** — Chladni interference, Lissajous pairs,
  spectrogram, phase portrait, chord convergences.
- **Misc** — Tenney dissonance + harmonic entropy meters, cents wheel,
  octave color mapping.
- **Journal** — snapshot notes that capture the full state of the moment
  (`ExoSnapshot` JSON) and snap to phase nodes on every circle.

### ExochronometerMac (macOS observatory)
Freeform widget canvas (drag/lasso layout, presets) hosting all sixteen
widgets (see WIDGETS.md), plus:
- **Snapshot mode** — pin every widget to any captured instant; the whole
  panel is a pure function of timestamp.
- **Trigger engine** — rules that fire PNG+caption captures on geometry
  peaks, boundaries, and meter thresholds, with cooldowns, dry-run mode,
  and a year-long simulation calibrator (Calibration menu, ⌘⇧K).
- **X auto-poster** — optional posting of fired triggers via the X API
  (OAuth 2.0; credentials live in the Keychain, never in the repo).

### ExochronometerWidget (WidgetKit)
Configurable home-screen (`.systemLarge`) and lock-screen
(`.accessoryCircular`) chronometer. Pick the timeframe per instance; add it
multiple times for multiple views. Minute is excluded (widget refresh
cadence makes it useless).

### ExochronometerCore
Pure-Swift shared framework: time/moon/geometry math, fade and winding
activation, harmonic tones, dissonance/entropy, chord detection and
forward projection, JI mapping, snapshot codec, SwiftData journal model.
Both apps and the widget link it, so every surface computes the same state.

## Build

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
xcodegen generate
open Exochronometer.xcodeproj
```

Schemes: **Exochronometer** (iOS), **ExochronometerMac** (macOS). Pick a
simulator or `My Mac` and ⌘R.

### Running on a physical iPhone (no paid Developer Program)

1. Plug in your device, trust this Mac.
2. Xcode → Signing & Capabilities → set your free Apple ID as the team.
3. Build & run; the personal provisioning profile expires after 7 days.
4. [AltStore](https://altstore.io) or [SideStore](https://sidestore.io)
   can re-sign over Wi-Fi.

## Project layout

- `ExochronometerCore/` — shared math + models framework
- `Exochronometer/` — iOS app
- `ExochronometerMac/` — macOS observatory (`Widgets/`, `X/`)
- `ExochronometerWidget/` — WidgetKit extension
- `Tools/` — app icon generator
- `project.yml` — XcodeGen spec; re-run `xcodegen generate` after editing

App and widget share the `group.com.alchemicav.exochronometer` App Group
so journal data is readable by the widget.

## Open items

Tracked in [DECISIONS.md](DECISIONS.md#open-items): meter recalibration
after the winding-tone change, episode dedup for chord posts (watch item),
knob sensitivity analysis, and the conjecture experiments.
