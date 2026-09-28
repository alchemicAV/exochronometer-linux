# Exochronometer for Linux / Omarchy

Port of [`alchemicAV/exochronometer-ios`](https://github.com/alchemicAV/exochronometer-ios)
to a native Linux desktop app running on Omarchy's own Qt6/QML stack.

**The Core framework is fully ported** — all 18 of its non-Apple files, plus two
pieces of pure logic rescued from SwiftUI view files. Nothing in
`ExochronometerCore` is unported.

## Running it

```bash
exochronometer              # from any terminal
gtk-launch exochronometer   # via the .desktop entry
```

Or pick **Exochronometer** from the application launcher / `omarchy-menu`.

Keys: **Tab** (or `1`–`6`) switches page, **q** / **Esc** quits.

Pages so far:
- **CIRCLES** — six separate circles (year, moon, quarter moon, day, hour,
  minute), each with a breathing `{n/k}` inscribed geometry, an indicator dot,
  its `traditionalLabel` centred, and node date labels outside the rim.
  Journal notes appear here as `NoteIndicator`s — a black disc with a white ring
  on the snapped node, showing a count when several notes share it — faded by
  the same breathing opacity as the geometry. Under the circles sits the
  `JournalInput` capsule: type a note, press Return or the glyph, and an
  `ExoSnapshot` is captured and filed. A **CIRCLES | SELECTORS** toggle
  (`CirclesPage.modeToggle`, persisted under `circlesPage.useSelectors`)
  switches the page to each timeframe's `ConvergenceSelectorChart` — the
  (divisions x degrees) integer-convergence lattice, scoped to that one frame,
  with the original's panel labels and its full-width stacked layout. Each
  circle also redraws at its own rate rather than the page's
  (`CirclesPage.refreshInterval`: 15 Hz for the minute hand down to 0.033 Hz for
  the year), which is where most of the page's cost went.
- **PEAK CALENDAR** — the 22 geometric-peak months, with the current month and
  day highlighted. Opens centred on the current month rather than at the top,
  clamped so a month near the end lands at the bottom instead of overscrolling.
- **GEOMETRY HARMONICS** (now MISC mode 9, no longer a page) — the ten `{n/k}` geometries per timeframe, each drawn
  as a polygon in a circle with its ratio, shape name, period and named interval
  (`FrequencyMath` + `intervalNames`). The **ALL HARMONICS** toggle switches to
  the full 6-timeframe table with frequency, period and closest 5-limit JI note.
- **MISC** — `MiscPage` with its nine modes, switchable via the picker
  (PHASE, CENTS, DISSONANCE, CHLADNI, SPECTROGRAM, CHORDS, COLOR, LISSAJOUS,
  SELECTOR). The original's timeframe filter applies everywhere except COLOR
  and CHORDS:
  - **DISSONANCE** — the Tenney dissonance and harmonic entropy meters, as
    per-pair averages over the live tone set at scale 23, with the original's
    timeframe-exclusion filter, its fundamentals-off default, and the red
    spillover past 100%.
  - **CONVERGENCE** — the cross-timeframe chord detector: the chord sounding
    *now* (with its fit in cents) and the next 30 days of convergences, nearest
    first, each with its fit and duration (`ChordDetector` + `ChordProjector`).
    The 30-day projection is cooperatively sliced so the UI stays responsive,
    and its result is cached in `QtCore` `Settings` (category
    `exochronometer-convergence`) under the original's recompute key, so
    reopening within the same 5-minute bucket restores instantly. A rescan keeps
    the previous results on screen rather than blanking to "…computing".
- **TIMELINE** — the journal as a vertical spine with each note flagged on it,
  newest first, spaced proportionally to the gap since the note above
  (`TimelineView`'s `pxPerHour` / `minGap` rule) with the original's zoom bar
  (0.25x–8x).
- **SPECTRUM** — `HarmonicAnalysisPage`: the live harmonic spectrum. A frequency
  axis (log or linear) with a bar per sounding tone, its amplitude as length, a
  dot at the tip, and a label naming timeframe, harmonic, octave scale, frequency
  and waxing/peak/waning state. Below it the composite-waveform scope sums the
  same tones into a 30 ms window. Three scale modes (`2^23`, `2^26`, `MERGED`,
  which opens by default), a timeframe exclusion filter, and the **SYNTH** panel
  editing `SynthParams` (envelope, tone, space, movement, and the orange
  "alters the chord" timbre block) persisted across restarts.

  The audio engine (`HarmonicAudio`, built on AVFoundation) is genuinely absent
  on this platform, so the AUDIO toggle, the volume row and the audio push are
  dropped — the synth knobs edit and persist real parameters, they just make no
  sound.

The journal is stored in `QtCore` `Settings` under the category
`exochronometer-journal`. A note holds its timestamp and the degree of every
timeframe at capture, which is what `NoteSnap` consumes; the original's
per-note snapshot JSON is not persisted, as nothing reads it back.

From source, without installing:

```bash
./node_modules/.bin/tsc && node scripts/build-app.mjs
qml6 build/app/main.qml
```

## Why not Swift on Linux

The iOS project has four targets. The UI is 100% Apple-only — SwiftUI, AppKit,
WidgetKit, SwiftData, AVFoundation, AppIntents and ScreenCaptureKit do not exist
on Linux (52 `import SwiftUI` lines). **The UI is a rewrite no matter what.**

What *is* portable is the math:

| | Lines | Status |
|---|---|---|
| Foundation-only (18 files) | 2,399 (69.8%) | **ported and numerically validated** |
| Apple-bound (6 files) | 1,040 (30.2%) | AVFoundation / SwiftUI / SwiftData |

The reason this port is TypeScript rather than Swift is the *frontend*: keeping
the core in Swift would need a Swift↔QML bridge, and the core is `Double` + trig
that translates to JS almost line-for-line. One language, no bridge. The Swift
build is still kept under `reference/` as the correctness oracle.

Logic that was pure but lived inside SwiftUI files was extracted rather than
abandoned — `defaultShapes` (from `GeometryOverlayView.swift`), the node-label
math (from `TimeCircleView.swift`), and `intervalName` (from
`GeometryHarmonicsPage.swift`). Each is validated against a verbatim copy of the
original function.

## Layout

```
src/core/          TypeScript port: 18 Core modules + 2 view-extracted
src/qml/main.qml   the app surface
test/validate*.mjs one validator per porting group
reference/
  swift-ios/       the original iOS checkout
  swift-core/      the portable files as a SwiftPM package + VectorGen
  vec-*/           per-group Swift vector emitters
  vectors-*.json   reference vectors
packaging/         PKGBUILD and package assets
dist/              tsc output
build/app/         QML-loadable .mjs + main.qml (what ships)
```

## Build, validate, package

```bash
npm install
./node_modules/.bin/tsc          # compile the core
node scripts/build-app.mjs       # assemble build/app (rewrites .js -> .mjs)
./scripts/make-package.sh        # builds exochronometer-<ver>-any.pkg.tar.zst
```

Regenerating a group's reference vectors (needs `swift-bin`):

```bash
export PATH="/usr/lib/swift/bin:$PATH"
cd reference/vec-<group> && swift build -c release
TZ=UTC .build/out/Products/Release-linux-x86_64/Vec<Group> > ../vectors-<group>.json
```

## Validation

Every ported module is diffed numerically against the *original Swift*, via
vectors emitted from a SwiftPM package that links the real core.

| Validator | Scope | Result |
|---|---|---|
| `validate.mjs` | 1,484 samples · 9,060 harmonic rows · 14,760 fade rows | PASS (UTC + NY) |
| `validate-nodelabels.mjs` | 2,220 node dates + labels | PASS (UTC + NY) |
| `validate-freq.mjs` | 2,291 values · all format strings byte-identical | PASS |
| `validate-dissonance.mjs` | 13,294 values | PASS |
| `validate-calendar.mjs` | 22 months · 16,360 positions · 1,008 snaps | PASS (UTC + NY) |
| `validate-analysis.mjs` | 254,552 values | PASS |
| `validate-chords.mjs` | 137,973 values · 7,545 identity-ordered lists | PASS |

Largest deviation anywhere is **5.28e-7°** on the minute hand — one ULP of
`Double` at that timestamp magnitude. Most fields are exact.

## Pitfalls found (all cost real debugging time)

1. **QML's V4 engine rejects the ES2019 optional catch binding** (`catch {`).
   It is a *parse* error, so the whole module fails to import and the app dies
   with only `qml: Did not load any objects, exiting.` — no line number, no
   cause. Always write `catch (e)`. tsc emits `catch {` verbatim for
   `try {} catch {}`, so this is easy to reintroduce.
   **BigInt is the same trap**: `1n`, `100n`, `x % 2n` are parse errors in V4,
   so a module using BigInt kills the whole app identically. Exact integer
   arithmetic must avoid it — e.g. round a `toFixed(20)` decimal expansion
   digit-wise instead, which turned out to reproduce printf exactly.

2. **QML `color` properties do not parse CSS `rgba()` strings.** `color:
   "rgba(255,255,255,0.04)"` silently fails to create the object. Use
   `Qt.rgba(1,1,1,0.04)` or `"#0affffff"`. (Canvas 2D `strokeStyle` strings are
   fine — those go to the JS context, not QML.)

3. **QML has no `Intl` timezone database.** `Intl.DateTimeFormat()
   .resolvedOptions().timeZone` returns `"UTC"` for *every* zone, so a UTC-4
   machine would display a flat lie. Detect it by cross-checking
   `getTimezoneOffset()` and fall back to a numeric label (`UTC-04:00`).

4. **JS `Date` time values are TimeClipped to whole milliseconds.** Storing an
   intermediate timestamp (e.g. a computed cycle boundary) as a `Date` silently
   discards sub-millisecond precision that Swift retains in its Double-backed
   `Date`. Keeping such values as plain numbers dropped a 7.7e-8 drift in
   `nodeActivation` to 1.9e-11.

5. **`String(format: "%.2f")` is not `toFixed(2)`.** C printf rounds the exact
   binary value of the double and resolves ties to *even*; `toFixed` resolves
   ties *away from zero*. Worse, pre-multiplying by 100 to round that is wrong
   twice over — `0.005 * 100` lands on `0.49999999999999994`. The port decomposes
   the double's decimal expansion (`toFixed(20)`, which is exact for doubles in
   this magnitude range) and rounds digit-wise, deciding an exact tie by
   comparing digits rather than by a floating-point guess. It must NOT use
   BigInt — see pitfall 1. Caught by the validator on 5 of 2,291 values;
   `printfFixed(x, digits)` now covers 0–3 decimals and is verified on 6,667
   vectors, all byte-identical.

6. **`swift-bin` puts its toolchain in `/usr/lib/swift/bin` but the driver
   resolves sibling tools from `/usr/sbin`.** Only `swift`, `swiftc` and
   `sourcekit-lsp` are symlinked there, so release builds fail with
   `unable to spawn process '/usr/sbin/swift-autolink-extract'`.

7. **`yay` cannot install AUR packages when `sudo` has no TTY** (`sudo: a
   terminal is required to read the password`), and `sudo -v` does not help
   because Arch enables `tty_tickets`. Build with `makepkg` (no sudo needed),
   then install the artifact with a direct `sudo pacman -U`.

8. **Swift's `JSONEncoder` omits `nil` rather than emitting `null`.** A
   validator comparing against those vectors sees `undefined`, not `null`, so
   `x === null` checks fail on every genuinely-absent value. Use `x == null`.

9. **A repeating QML `Timer` with `interval: 0` never fires.** Setting it to
   `1` makes it tick. This silently stalls any cooperative-slicing loop built
   on a zero-interval timer: the work sits at "0%" with no error and no stack.

10. **QML bindings do not observe mutations *inside* a JS object held in a
    `property var`.** When a resumable worker mutates `scan.i`, a binding
    reading `scan.i` keeps its stale value — the property's identity never
    changed, so nothing is notified. Mirror the moving value into a real QML
    property (`property real progress`) and bind to that instead.

11. **`console.log` produces no output in this Qt build.** Every QML failure
    described in this file was silent: `qml6 app.qml` prints nothing, not even
    for a `console.log` in `Component.onCompleted`, and `QT_LOGGING_RULES`
    does not bring it back. Surface diagnostics through the UI — a `debugText`
    string property rendered as red text — or you will debug blind.

12. **QML's JS is single-threaded, and V4 is ~10x slower than V8.** The 30-day
    chord projection measured 727 ms in node but 7,036 ms in QML, freezing the
    UI solid. The scan was refactored into `beginUpcoming` / `stepUpcoming` /
    `finishUpcoming` so the view can advance it in ~25 ms slices across frames:
    9,181 ms wall time, UI responsive throughout, with `upcoming()` kept as a
    one-shot wrapper. Slicing is provably behaviour-preserving — for 4 window
    configurations and budgets of 0.5 ms / 5 ms / 1000 ms the sliced result is
    byte-identical to the one-shot call, and the chords validator still passes.

13. **Compare a recompute key against itself, never against part of it.** The
    convergence view stores a composite `bucket|fundamentalsOff` key, but its
    timer compared that against the bare bucket — so they never matched, the
    scan restarted every second, nothing ever completed, and the cache stayed
    empty. The symptom was a progress bar stuck near 0% with no error at all.
    Both sides must call the same `currentKey()`.

14. **`visible: false` does not stop a `Canvas` from repainting.** Hiding a page
    stops *rendering*, not `requestPaint()` — an invisible canvas (and one whose
    *parent* is invisible) runs `onPaint` exactly as often as a visible one;
    measured 158 paints for each of the three shapes. So gating a whole page on
    `visible` saves nothing, and every view needs an explicit flag. This is what
    made every page in the app cost the same ~101% of a core no matter which one
    was on screen.

15. **Qt rasterises Canvas paths on the CPU, and stroking a long
    self-intersecting path is pathologically slow.** The phase portrait's curve
    is one 800-point trace that crosses itself repeatedly — and the crossings
    are inherent to the original's own parameters, not a porting artifact: its
    hour tones are 14-18.6 kHz against a 13.3 kHz Nyquist for 800 samples over a
    30 ms window, so they complete up to 559 cycles that the sampling cannot
    represent, and consecutive samples jump up to 680 px. That is what makes the
    STANDARD portrait the dense mesh the legend calls a "dense filled region".

    Measured at the real page rate, two 12 s windows each: one `ctx.stroke()` of
    the whole path **101.3% / 101.1%** (it alone cost more than the rest of the
    app), one stroke per segment 32.1% / 37.7%, chunks of 16 points no better,
    and `ctx.antialias = "none"` no help at all. The same trace drawn as a run
    of 2x2 `fillRect` squares stepped every 2 px: **22.6% / 22.4%**.

    Two traps in getting there. Truncating the squares (capping the count) is
    much cheaper but *wrong*: the tail collapses to scattered dots, which reads
    as a broken plot rather than a dense mesh. A complete trace needs ~112k
    squares typically and up to ~200k, so the cap has to be a runaway guard set
    well above that, never a normal limit. And fill primitives avoid the stroker
    entirely — reach for them when a Canvas path is hot. Cost tracks the
    *covered area*, so canvas size is a lever too.

16. **QSettings treats a line starting with `[` as a section header.** String
    values are written quoted (`key="[{...}]"`) so this is normally safe — but a
    *botched* edit that strips the opening quote leaves raw JSON starting with
    `[`, and the next read silently parses it as a section, dropping the value.
    Worth knowing when hand-repairing a `Qml Runtime.conf`.

## Performance: only what is on screen

The app was at ~101% CPU (a full core) on **every** page, and ~101% on every
Misc mode too — the cost was flat, which is the signature of work that does not
depend on what you are looking at. Two mechanisms caused it:

1. A global 15 Hz timer rebuilt `root.snapshot`, and **every** view had
   `Connections { target: x; onSnapshotChanged: canvas.requestPaint() }`. Since
   `visible: false` does not stop a Canvas repainting (pitfall 14), all six
   pages and all ten MISC modes repainted continuously.
2. The heavy derived bindings (`activeTonesForScales`, the Tenney/entropy pair
   maths, the Lissajous pair enumeration) recomputed on every one of those ticks,
   hidden or not.

The fix is an explicit `live` flag per view, ANDed down the tree — a page is
live only if it is the current page, and a MISC mode only if it is also the
selected mode — combined with a per-page clock instead of one global rate:

| page | clock | why |
|---|---|---|
| CIRCLES | 15 Hz | minute hand must move smoothly |
| MISC | 5 Hz | animated analysis views |
| SPECTRUM | 2 Hz | slow readout |
| PEAK CALENDAR / GEOMETRY HARMONICS / TIMELINE | stopped | static; refreshed on entry |

Hidden views now also skip their derived bindings, the spectrogram's 400-frame
rebuild is gated on being visible, and the 30-day chord scan does not start
until its view is shown. Arriving on a page refreshes once immediately, and each
view repaints on becoming live, so nothing shows stale data.

Measured with `scripts/measure-pages.py` (instantaneous CPU from
`/proc/<pid>/stat`, the window focused before sampling, 12 s window):

| page | before | after |
|---|---|---|
| CIRCLES | 102.2% | **5.4%** |
| PEAK CALENDAR | 102.2% | **0.0%** |
| GEOMETRY HARMONICS | 102.5% | **0.0%** |
| MISC | 100.8% | **2.4%** |
| TIMELINE | 101.7% | **0.0%** |
| SPECTRUM | 102.5% | **3.3%** |

Two further cuts came from following the original rather than inventing: CIRCLES
was redrawing all six circles at the page clock's 15 Hz, when
`CirclesPage.refreshInterval` gives each its own rate (the year hand advances
0.033 degrees *per second*), taking it from 21.7% to 5.4%; and the phase curve
was being drawn with a stroke, which pitfall 15 covers.

MISC's figure moves with the phase trace's complexity — the trace is a mesh
whose length depends on the tone set, so it measured 13.2% on another run. Every
other page is stable.

Isolating the remainder inside MISC found the app's single most expensive
operation: the phase portrait's one 800-point `ctx.stroke()`.

Two measurement traps are worth recording, because both produced numbers that
were wrong rather than merely noisy: `ps`'s `%cpu` is a lifetime average and
says nothing about what the process is doing *now* (read `utime+stime` deltas
from `/proc/<pid>/stat` instead), and Qt throttles a window the compositor is
not showing, so a sweep that does not focus the window measures the wrong
thing. Even so, readings for a CPU-bound view were bistable — it either kept up
or saturated a core — so the harness samples for 12 s and the figures above are
reproducible rather than single-shot.

## Two hosts, one instrument

The app can be driven by two different hosts, and they share one implementation:

```
src/qml/AppShell.qml        the whole instrument (state, tab bar, all 5 pages,
                            all 9 MISC modes, journal, footer, shortcuts)
src/qml/main.qml            host 1: a thin Window that just embeds AppShell
src/omarchy-plugin/         host 2: the Omarchy shell plugin
   manifest.json            plugin manifest (kinds: bar-widget)
   BarWidget.qml            bar label + panel lifecycle
   Panel.qml                extends qs.Ui's Panel and hosts the same AppShell
```

`AppShell` is host-agnostic: the only host-specific behaviour is `allowQuit`,
because the standalone window's `q`/`Escape` shortcuts must not quit the user's
whole shell when the same component runs inside a panel. Moving the app into
`AppShell` was verified as a **verbatim** move — 1120 lines to 1120 lines with a
single diff hunk, the two gated shortcuts — so the standalone app behaves
exactly as before.

The plugin is **generated, never hand-maintained**:

```bash
node scripts/build-app.mjs             # compile core + assemble the window app
node scripts/build-omarchy-plugin.mjs  # generate build/omarchy-plugin/
bash scripts/install-omarchy-plugin.sh # copy into the shell config + restart
```

`build-omarchy-plugin.mjs` copies the app's compiled core and every UI component
(except its window host, which the plugin replaces with `Panel.qml`) and adds the
three plugin files from `src/omarchy-plugin/`. So the bar widget's degree comes
from **the same compiled core the validators check against the Swift oracle** —
the bar reads `YR 276.4°` while the app's year circle reads `276.40°`, because
they are the same code, not two implementations that have to be kept in step.

### The bar widget

Shows the instrument's own date and the angle of one timeframe:

```
Quartis 7  HR 82.9°
```

`Quartis 7` is the exochronometer's date — day 7 of Quartis, month 18 of the
year's 22 Farey-peak months — read straight off the ported peak calendar, the
same `position()` its Peak Calendar page uses. `HR 82.9°` is the preferred
timeframe's angle, recomputed once a second.

The preferred timeframe is chosen on the CIRCLES page, next to CIRCLES |
SELECTORS, and defaults to **hour**. The WIDGET owns it, not the page:

```qml
property var preferredBridge: null
readonly property int preferredTF: {
    const src = preferredBridge ? preferredBridge.preferredTF : circlesStore.preferredTF
    return (src === undefined || src === null || isNaN(src)) ? 4 : src
}
function setPreferredTF(i) {
    if (preferredBridge) preferredBridge.setPreferredTF(i)
    else circlesStore.preferredTF = i
}
```

That shape exists because of the persistence gap below: the page's chips cannot
write QtCore `Settings` inside the shell, but the widget's `shell.json` setting
does survive a restart. So the panel points `preferredBridge` at the widget, and
the widget is the single source of truth — the chips bind to it, and a right
click on the bar steps the same value.

Left click opens the full instrument as a panel, middle click launches the
standalone window. It exposes the shell's popout contract
(`open`/`close`/`opened`/`closeForPopoutSwitch`) and an `IpcHandler`:

```bash
omarchy-shell alchemicav.exochronometer toggle
omarchy-shell alchemicav.exochronometer preferredTF
```

### Theming

The instrument follows the system theme in both hosts, by two different routes:

| host | where the palette comes from |
|---|---|
| standalone app | its launcher reads `~/.local/state/omarchy/current/theme/colors.toml` and passes `--theme-bg`/`--theme-fg`/… as **command-line arguments** |
| shell panel | the shell has already loaded the palette, so the panel takes it from `qs.Commons`' `Color` |

The app cannot read the files itself: `XMLHttpRequest` against a `file://` URL
returns an **empty response** in this build (verified, exit-code probe), while
`Qt.application.arguments` works fine. Without a theme present the launcher
passes nothing and `core/theme.mjs` keeps its own deliberate fallbacks.

Two things this ran into, worth knowing before touching it again:

- **A `qmldir` in the app root breaks every component.** Listing one type turns
  the directory into a module, and then only the listed types resolve -
  `AppShell`, `MiscPage`, … all fail with `Did not load any objects`. Verified
  cleanly: all 17 components failed with the qmldir present and all 17 loaded
  again once it was removed. A singleton needs its own subdirectory instead.
- **A `pragma Singleton` in a directory module appeared to abort the engine**
  (SIGABRT, no diagnostic). Treat that as provisional: the ad-hoc `QtObject`
  probes used to establish it turned out to be unreliable in their own right -
  they later failed even on a no-op file - so the evidence is contaminated. The
  JS module is the right choice regardless: `core/*.mjs` is what this codebase
  already does everywhere, and it needs no `qmldir` at all.

An earlier draft of this file also blamed ES2018 object spread for a module
failing to load. That was **not** established - the same broken probes were in
play - so it is not a claim this project should make. `configure()` is written
out key by key for clarity, not for correctness.

Because a JS module's exports are **not observable**, the palette has to be in
place before the views are built. Both hosts guarantee that by loading
`AppShell.qml` through a `Loader` they activate only *after* configuring:

```qml
Component.onCompleted: {
    Theme.configureFromArgs(Qt.application.arguments)
    color = Theme.background()      // the Window's own binding is too early
    shell.active = true
}
```

That ordering is the load-bearing part: with a direct child, `AppShell` would
read the fallback palette and never update. A theme change mid-session is not
supported - relaunch to pick one up.

### Audio (SPECTRUM)

**PLAY sustains until STOP.** There is no loop toggle, because with the default
player there is nothing to loop: a continuously-pulled sink runs until it is told
to stop. The readout says so, and reports the sink's own state:

```
AUDIO  playing · 44100 Hz · 2 ch · active · live 5.0s · 52 voices
```

#### The real-time path (default)

Qt6 exposes **no raw-sample sink to QML** - `AudioEngine`, `AudioSink`,
`AudioBufferOutput` and `AudioSource` are all C++-only, and the QML-visible
`MediaPlayer`/`SoundEffect` only accept files and buffers. So continuous sound
needs C++, and it is built as a QML module: `src/audio/` compiles to
`ExoAudio` (`libexoaudio.so` + `qmldir`), installed to
`/usr/lib/qt6/qml/ExoAudio/` so both hosts import it with no environment setup.

The split keeps the port honest. **JS still decides the sound** - which tones, at
what amplitudes, from the same geometry the charts draw - and **C++ only
oscillates**, at 44.1 kHz, where the arithmetic is nothing:

| | |
|---|---|
| `core/wavRender.ts` (`expandVoices`) | the tone bank -> voices: unison detune, partial gains, constant-power pans, the Nyquist guard |
| `audio/exosynth.cpp` (`Synth::expand`) | the same table, plus the running oscillators |
| `audio/realtimeaudio.cpp` | `QAudioSink`, the pull device, the voice slews |

`Synth` is pulled by the audio thread and fills blocks on demand, so playback
starts on the first sample and never ends on its own. Each voice slews toward its
target gain over `attackMs`/`releaseMs`, which is also what keeps a bank that
changes *under* the music from clicking - and why the bank can follow the
geometry live (`RealtimePlayer.qml` re-reads it every 500 ms) instead of being
frozen at the moment PLAY was pressed. The renderer normalises to the buffer's
peak; a continuous stream has no future peak to normalise against, so it tracks a
smoothed one instead.

**Verified by cross-implementation agreement.** AVFoundation exported no numbers,
so there is no Swift oracle for audio. Instead `test/validate-realtime.mjs`
compares the C++ kernel against the JS one - the same inputs, the expanded voice
table entry for entry, then 512 frames x 2 channels per case, in four
configurations (`pure`, `pad`, `space`, `tremolo`). This is not ceremony: it
caught a real bug in the C++ matcher, which keyed a new bank against the sounding
one by frequency **alone**. Two different partials can land on the same frequency
(220 x 3 and 330 x 2 are both 660 Hz), so they were merged instead of summed -
14 voices where 16 were asked for, at half level. Each existing voice is now
claimed at most once.

The cost of this design is the caveat it was accepted with: the app package is
`arch=('x86_64')`, not `any`.

#### Two audio bugs, and the lesson is that only one of them was audible

**Bug 1 - voice churn (real, but not what he was hearing).** The kernel needs no
audio device to run, so this was reproduced headlessly: `exo-selftest drift`
rebuilds the bank every 500 ms from a *moving* geometry, plays it through
device-sized blocks, and prints a 25 ms envelope. That showed the voice table
growing from 144 to **504 voices for a 72-voice bank** and the envelope swinging
**3.5x peak-to-trough, modulated at exactly the rebuild rate** - because the voice
matcher identified "the same voice" by an exact 0.01 Hz frequency match, and a
bank rebuilt from a moving geometry always comes back slightly retuned. The fix
matches the **nearest** unclaimed voice within 2% of the frequency, retunes it in
place, and retires faded voices every rebuild: **72 voices, 1.12x swing**,
unchanged at 256/1024/4096-frame blocks. The readout carries a voice high-water
mark (`58 voices (peak 58)`) so a table that starts accumulating is visible
without listening.

That was all true, and the audio was **still choppy**.

**Bug 2 - the declared format did not match the bytes written (the audible one).**
`readData()` treated any non-Float format as Int16. This machine's default sink is
**`s32le`**, so Qt negotiated **Int32** - and the device was handed 2-byte samples
in a stream it had been told was 4-byte. The sink consumes by `bytesPerFrame`, so
it drained this device **twice as fast as it should**, starved, and played roughly
half of every 46 ms as silence: 33% of the output was silence in 16 ms gaps, a
~21 Hz stutter. That is precisely "buffering", and precisely what it sounded like.

Every engine-side measurement was clean while this was happening - the kernel
cross-check compared the synthesis, the envelope reproduction compared the kernel,
and every counter on screen reported success. **None of them could see it, because
none of them looked at the device.** What found it was recording the sink's
monitor and measuring the output directly:

```
before:  262 silence gaps, 16 ms each, every 47 ms   ->  33% silence
after :  1 gap, at the very start of the recording   ->   0% silence
```

`readData` now writes Float, Int16, Int32 and UInt8 correctly, matching the format
it was given (`48000 Hz S32` in the readout), and the format is negotiable via
`requestedRate` / `requestedFormatName` so the choice can be tested rather than
assumed. Both hosts play through that same module - the standalone window and the
toolbar panel's Quickshell panel - so the fix reaches the panel with it; the test
below still checks each host separately, because a fix that landed in only one of
them would otherwise pass.

`test/validate-device-audio.mjs` is the regression test: it records the device
while each host plays and fails on any silence after the start (4 checks over 2
hosts; currently `0.00% / 0.00%`). It skips - exit 77, reported as SKIP rather than
PASS - where there is no audio output, no display, or no host. It was verified to
**fail** against a deliberately broken build (50.16% silence), so it is a check
that can actually fail.

#### The fallback path

If the module cannot be imported - a different architecture, or a host without it
- the `Loader` in `HarmonicSpectrumPage.qml` reports an error and falls back to
`SynthPlayer.qml`, which renders a WAV in JS and hands `MediaPlayer` a `data:`
URL: no filesystem, no C++. This backend does **not** honour `MediaPlayer.loops`
for an in-memory buffer, so the repeat there is done explicitly on `EndOfMedia`,
and the player exposes a `loopCount` that can only rise if playback genuinely ran
past the end. An earlier version relied on `loops`, and the verification of it was
worthless - the check had removed the very handler that would have reported the
sound stopping, then treated "playing" as proof.

That render is synchronous on the GUI thread and costs **~1.2 s** for a 3 s
stereo buffer through the full voicing chain, so it is deferred one event-loop
turn behind a `rendering…` status - otherwise the press looks ignored. Mono or
stereo 44100 Hz (the hour tones reach ~16 kHz), a 10 ms fade at each end (a buffer
that starts mid-cycle clicks), peak-normalised to 0.9 (the sum routinely exceeds
1.0; one scale factor, so the relative amplitudes the chart shows survive).
Measured on this box for a 2 s buffer: **rendered in 119 ms**, 256 kB of data URL.

Both files expose the same surface (`tones`, `shape`, `play`, `stop`, `toggle`,
`playing`, `statusText`, `detail`), so the page does not know which one it has.

**The SYNTH panel now shapes what you hear.** The tone bank stays fixed by the
geometry; `SynthParams` only shapes how it is rendered, which is the same split
the original draws. The pipeline, in the order it applies them:

| parameter | what it does in the render |
|---|---|
| `unisonVoices` + `detuneCents` | copies per tone, spread in cents, each with its own phase so the copies are decorrelated rather than just louder |
| `partials` + `enrichment` + `partialTilt` | integer harmonics, gain `enrichment / k^tilt` |
| `width` | constant-power panning of the copies - stereo only when there is something to decorrelate |
| `tremoloRateHz` + `tremoloDepth` | sub-audio amplitude LFO |
| `lowpassHz` | one-pole low-pass, 6 dB/oct |
| `reverbMix` + `reverbPreset` | Schroeder comb + allpass network, scaled per preset |
| `attackMs` + `releaseMs` | applied by the **player** as a volume ramp, not baked in - a sustaining loop must not re-swell on every pass |

Two properties are load-bearing and are checked rather than assumed:

- **Nothing is fabricated above Nyquist.** Adding partials to a 16 kHz hour tone
  would otherwise alias harmonics *down* into the audible band as frequencies the
  chord does not contain - the one thing the information-safe half of the
  parameter set exists to avoid. Checked by rendering a 16 kHz tone with six
  partials and asserting it is bit-identical to the same tone without them.
- **The loop seam is continuous.** The player sustains by repeating the buffer,
  so the renderer crossfades the tail back into the head. Checked by asserting the
  wrap-around step is no worse than the largest step inside the buffer.

`test/validate-wav.mjs` runs 75 checks over all of this. Writing them turned up
three of my own mistakes, all from forgetting that the renderer peak-normalises
its output: attenuating a lone sine is then undone by the gain, and three copies
of one frequency sum to *one* sine (which is exactly why that parameter is called
information-safe). Those checks now measure the **spectrum** with a Goertzel
probe instead of comparing levels.

`test/validate-wav.mjs` is one of two validators with no Swift oracle —
AVFoundation exported no numbers — so it checks what can be checked: the samples
against an **independent** evaluation of that same sum, the RIFF header field by
field, the 16-bit round trip, and `ffprobe` reading the buffer back as
`pcm_s16le 44100 Hz mono`. The other is `test/validate-realtime.mjs`, which has
something better than an oracle: a second implementation (the C++ kernel) that has
to agree with this one.

### Layout changes in this round

- **`src/audio/` (new)** - the real-time kernel and the QML module it is wrapped
  in: `exosynth.{h,cpp}` (the sample generator), `realtimeaudio.{h,cpp}`
  (`QAudioSink` + the pull device), `plugin.{h,cpp}` + `qmldir`, and
  `selftest.cpp` (the cross-validation harness, which links with no Qt at all).
  Built by `scripts/build-audio.sh` - not cmake, since it is one shared object and
  one test binary, and the hardening flags makepkg would apply are passed by hand.
- **`src/qml/RealtimePlayer.qml` (new)** - the default player. `SynthPlayer.qml`
  stays as the fallback; the page's `Loader` picks between them.

- **GEOMETRY HARMONICS left the tab bar** and became MISC mode 9. It is the same
  view, extracted verbatim into `GeometryHarmonicsView.qml`; the top bar is five
  pages, and the keyboard shortcuts are `1`–`5`.
- **MISC PHASE defaults to NORMALIZED**, which is also the cheaper trace
  (74k squares worst case across curves versus 200k for STANDARD).
- **MISC COLOR and SELECTOR keep a square footprint** (`side = min(w, h)`,
  centred) instead of stretching to the window.
- **SPECTRUM puts the synth settings BESIDE the chart.** The original REPLACES
  the spectrum with them, which is right on a phone and wasteful on a desktop;
  the SYNTH chip now just shows or hides the right-hand column.
- Every Canvas that gained a size change also gained a repaint-on-resize: a QML
  Canvas is **cleared, not repainted**, when it is resized.

### Verifying wide layouts on this box

hyprland TILES this app, so it runs about **621x670** — very nearly square.
Two consequences worth knowing before judging a layout change:

- Anything that depends on being wider than it is tall is invisible in the app's
  own window and only shows in the **panel** (1020 wide). That is where the
  square colour field and selector grid actually read as squares.
- `scripts/shoot-states.py` renders states through `grabToImage` at a fixed
  1020x760. Offscreen grabs of this app have been **unreliable for canvases that
  were resized** — they come back blank while the app itself draws them fine —
  so treat those shots as layout checks, not as proof a canvas renders.
  `scripts/shoot-wide.py` and `scripts/probe-square.py` render in a real window
  and capture with `grim`, which is the path the user actually sees.

Also: hyprland 0.56.2 here takes dispatchers as **Lua**, quoted as strings, so
the usual `hyprctl dispatch resizeactive exact 1020 760` form fails with a Lua
parse error rather than resizing anything.

### The bar's colour is a shell setting, not the theme

`omarchy bar transparent <true|false>` controls whether the bar paints its own
background. With `transparent: true` in `~/.config/omarchy/shell.json` the bar
renders transparently and shows the wallpaper through it - which reads as "the
bar lost its theme", and `omarchy theme set` does not fix it. The stock default
is `false`.

```bash
omarchy bar transparent false     # then: omarchy restart shell
```

Two things ruled out while chasing this: a bare `omarchy restart shell` does
**not** lose the palette (the bar comes back on `shell.toml`'s `[bar] background`
- verified by sampling the rendered bar, not by eye), and `omarchy bar put` does
**not** touch that flag, so the plugin installer cannot cause it.

### Known gap: no persistence inside the shell

`QtCore`'s `Settings` **cannot initialise inside Quickshell**:

```
QML Settings at .../AppShell.qml: Failed to initialize QSettings instance. Status code is: 1
QML Settings at .../AppShell.qml: The following application identifiers have not been set:
                                  QList("organizationName", "organizationDomain")
```

Quickshell never sets `organizationName`/`organizationDomain`, so `QSettings` has
no path to build and fails with `AccessError`. Consequence: in the panel, the
journal, the CIRCLES/SELECTORS mode, the synth params and the convergence cache
all fail to save, and four warnings appear in the journal on every shell start.
(Everything still *works* in-session — it just does not survive a restart.)

`Settings { fileName: ... }` is not a way out: this Qt build's `Settings` has no
`fileName` property at all (`Cannot assign to non-existent property "fileName"`),
which is worth knowing because the attempt breaks the whole component.

The fix is a small store abstraction rather than a patch: give the persisting
components an injected backend, with `QtCore` `Settings` for the window and a
JSON file for the plugin via Quickshell's `FileView` (`blockWrites: false`,
`atomicWrites`), which is the one file-write primitive a plugin has.

### A construction-order fix the panel exposed

`LissajousView`'s `Grid { model: parent.pairs.length }` threw
`TypeError: Cannot read property 'length' of undefined` into the shell's journal
five times per start. Instantiating the tree through the plugin's `Loader`
evaluates that binding before the delegate's `pairs` exists. Guarded
(`parent.pairs !== undefined ? … : 0`). The standalone app never showed it.

### Packaging: two packages on purpose

```
exochronometer            the app (any, no shell dependency)
exochronometer-omarchy    the shell integration (depends: quickshell, omarchy)
```

They are split because namcap was right about the combined version:

```
E: Dependency quickshell detected and not included
```

The plugin's QML imports `Quickshell`, `Quickshell.Io` and `qs.Ui`/`qs.Commons`,
so shipping it inside the app package would make a plain Qt6 program depend on
the shell — and would drag Quickshell onto machines that only want the window.
Packaging them separately keeps the app package clean and the dependency honest.

The plugin package installs the generated plugin under
`/usr/share/exochronometer-omarchy-plugin/` plus one helper; it never writes into
a home directory itself (a package must not), so the helper does that part:

```bash
exochronometer-omarchy-plugin install   # copy into ~/.config/omarchy/plugins, restart shell
exochronometer-omarchy-plugin check     # does the shell's copy still match the package?
exochronometer-omarchy-plugin remove    # disable, delete, and clean the bar layout
```

#### The copy under `~/.config` drifts, and nothing says so

The shell runs the plugin from `~/.config/omarchy/plugins/alchemicav.exochronometer/`,
which is a **copy** of this package. A symlink is not an option - omarchy's own
validator refuses it (`symlinks are not allowed inside a plugin folder`) - so the
copy is required, and **it does not follow package upgrades**.

That is not a cosmetic problem. The panel and the app are two copies of one
instrument, and a stale copy is invisible: the shell happily runs an old plugin
while the packaged one is current. It cost a whole round of debugging. The
standalone app was playing continuously after the real-time work, while the toolbar
kept "stopping by itself" - because the copy the shell was actually running
predated real-time audio entirely, still had no `RealtimePlayer.qml`, and was
playing through the old buffer player. Every check on the packaged tree passed. The
running copy was the one nobody was looking at.

Three things now guard it:

- `exochronometer-omarchy-plugin check` diffs the running copy against the package
  and exits non-zero when they disagree.
- The package prints a reminder from `post_install`/`post_upgrade`, which is the
  only channel pacman gives a package for this.
- `scripts/check-panel-audio.sh` answers the question that actually matters: is the
  shell running the real-time engine, is its copy current, and does the engine
  survive the panel closing?

Two things the helper learned the hard way:

- `omarchy plugin enable` is a **race** and was dropped. It runs before the
  restarted shell has booted, so the registry answers
  `PluginRegistry.setEnabled: unknown plugin …`. It is also unnecessary —
  `omarchy bar put` is what mounts the widget, verified working without it.
- A failed QML compile is cached in `~/.cache/quickshell/qmlcache` and keeps
  being reported after the source is fixed, so `install` clears it first.

The engine can also be traced when the question is "did it even get constructed?".
Tracing goes to a **file**, `/tmp/exo-audio-life.log`, and only when
`/tmp/exo-audio-trace` exists - nothing is written in normal use. A file rather
than logging, because neither obvious channel works here: `qml6` drops
`console.log` entirely, and Quickshell's message handler forwards only *named*
logging categories, so both `qInfo` and `qWarning` from the module are silently
discarded inside the shell:

```bash
touch /tmp/exo-audio-trace          # enable
omarchy restart shell               # then read what the shell really does
cat /tmp/exo-audio-life.log
```

That trace is what showed the panel's engine being constructed at shell boot and
**surviving the panel closing** - ruling out the lifetime theory and pointing at the
stale copy instead.

Remaining namcap notes, both benign: `qs.Ui`/`qs.Commons` are reported as
"uninstalled dependencies" because namcap cannot attribute them to the `omarchy`
package that provides them, and `qt6-declarative` is flagged as implicitly
satisfied (it arrives transitively via quickshell).

## Precision

Two independent representation gaps exist between the two languages, and both
are characterised rather than papered over:

**Whole-millisecond instants.** `TimeFrame.degree()` divides by small cycle
durations for the hour and minute hands, amplifying any error in the input
instant. Swift stores `Date` as a `Double` and derives its `nanosecond`
component from it, so at 2026 epoch magnitudes (ULP ≈ 2.4e-7 s) it reports e.g.
`566999912` ns for a timestamp written `.567`; JS `Date` reports `.567` exactly.
The two disagree by up to one ULP of *time*, and the port is the cleaner of the
two. `test/validate.mjs` derives its tolerance per timeframe from the ULP of the
input timestamp (`ulp / cycleDuration * 360`).

**Fractional-millisecond instants.** Where a vector names an instant with a
fractional millisecond (e.g. `1234567.891` ms), JS `Date` TimeClips the fraction
away while Swift's `Double` keeps it — a gap of up to 0.891 ms. Amplitude
depends on the degree through `cos`, whose slope is bounded by
`(π/2)/(fadeFraction × cycleDuration)`, so the induced error is bounded by
`slope × gap`. `test/validate-analysis.mjs` gates such rows against that derived
bound (max 1.296e-5, for the hour ring) and asserts every row whose instant *is*
on the ms grid at a flat 1e-9.

Neither gate was tuned to make a test pass: both are computed from the
mechanism, and each gated row is still asserted against its bound.

## Port status

**Ported and validated (20 modules):** all 18 Core files — `TimeFrame`,
`MoonPhase`/`PhaseEpoch`, `Geometry`, `JustIntonation`, `FrequencyMath`,
`FadeMath`, `ExoSnapshot`, `NoteSnap`, `ChordCatalog`, `ChordDetector`,
`ChordProjector`, `DissonanceMath`, `DissonanceGraph`, `DissonanceCalibrator`,
`HarmonicAnalysis`, `PeakCalendar`, `PhasePortraitMath`, `SynthParams` — plus
`timeLabels` and `intervalNames` extracted from the iOS views.

**Not portable (6 files, 1,040 lines):** `HarmonicAudio` (AVFoundation),
`ConvergenceSelectorView`, `GeometryOverlayView`, `HarmonicColor`,
`PeakMonthCell` (SwiftUI), `JournalNote` (SwiftData). Only the drawing and audio
playback are genuinely absent; the pure logic inside these files was extracted
and is ported.

**Wired into a page:** `FrequencyMath` + `intervalNames` (Geometry Harmonics),
`HarmonicAnalysis` + `DissonanceMath` (Misc / Dissonance), `ChordDetector` +
`ChordProjector` + `ChordCatalog` (Misc / Convergence), `NoteSnap` (Circles note
nodes), `SynthParams` (Spectrum / Synth panel).

**Wired into a page (cont.):** every remaining Misc mode — `PhasePortraitMath`
(PHASE), `CentsWheelView` (CENTS), `ChladniView` (CHLADNI), `SpectrogramView`
(SPECTROGRAM), `ColorMappingView` (COLOR), `LissajousView` (LISSAJOUS),
`SelectorView` (SELECTOR) — plus `HarmonicColor` (COLOR and PHASE), the journal
(`NoteSnap` + Timeline), and `HarmonicAnalysis` again for the Spectrum page.
All five pages and all ten MISC modes are implemented; nothing is left unwired.

**Genuinely absent features:** audio (was `AVFoundation`), the 16 macOS board
widgets, the trigger engine, the X auto-poster, and WidgetKit. These are UI and
platform features to rebuild on this side rather than port.

## Packaging note

`omacom/omarchy-pkgs` is the distro's curated set shipped to every Omarchy user;
a personal instrument does not belong there. This builds a normal local
package — install with `sudo pacman -U`, or publish to the AUR.