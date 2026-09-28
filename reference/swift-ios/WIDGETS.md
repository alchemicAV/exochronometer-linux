# Exochronometer — The Instrument Panel

Every widget, what it shows, and the math underneath. All of them read the
same state: the set of currently sounding tones, each a pure function of
the timestamp (see [THEORY.md](THEORY.md)). Unless noted, analytical
widgets exclude fundamentals by default and use the 2²³ octave lift.

---

## Time Circles (year · moon · ¼ moon · day · hour · minute)

The primary display. A dot sweeps each circle once per cycle:

```
θ(t) = 360° · (t − t₀) / P        t₀ anchored to the epoch (UTC)
```

Inscribed {n/k} polygons fade in as the dot approaches a vertex the
winding path visits this rotation — cosine envelope, full opacity on the
vertex, gone beyond ±10.8°. Star polygons traverse their n vertices over
k rotations, so a heptagram {7/3} lights on one of every three passes of
a given vertex. Journal notes appear as markers snapped to their phase.

## Peak Calendar

The year circle's geometry unrolled into a calendar. Every inscribed
polygon reaches an absolute peak — amplitude 1.0 — as the indicator
crosses one of its vertices, so the year's peak moments are the union of
all vertex angles for n = 3…8:

```
{ p/q  reduced  :  q = 3…8,  0 ≤ p < q }   =   F₈
```

That union is exactly the **Farey sequence of order 8** — every fraction
of the circle whose lowest-terms denominator is ≤ 8. It has 22 terms, so
the year has 22 peaks and 22 gaps between them. The gaps are
variable-length "months" summing to one mean tropical year:

```
length(i) = ( f(i+1) − f(i) ) · 365.24219 d      f = sorted F₈ terms
```

Because F₈ is symmetric about ½, the lengths are **palindromic**: month k
and month 23−k are equal. The two longest (45.7 d) straddle the December
solstice; the two shortest (6.5 d) sit just inside them; the tightest
packing is around the June solstice. The equinoxes fall in the mirror
pair 5 / 18.

### Naming

A peak p/q in lowest terms belongs to **harmonic q** — the simplest
polygon with a vertex there (2/8 is really 1/4, a Quart peak, not an Oct
one). Each month is `root(q) + suffix(p)`:

| q | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|
| **root** | Tert | Quart | Quint | Hex | Sept | Oct |

| p | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| **suffix** | ‑one | ‑ava | ‑is | ‑yr | ‑une | ‑em | ‑oz |

The root names the harmonic and its interval at once (quart = fourth,
quint = fifth, sept = seventh, oct = octave); the suffix is the vertex
numerator, so mirror twins read as complements — Octone 1/8 ↔ Octoz 7/8,
numerators summing to 8. The mirror's two fixed points, 0/1 and 1/2, get
their own names: **Initia** and **Meridia**. Each harmonic contributes
φ(q) months, and 1 + Σφ(q) = 22.

Shorthand is the root letter plus the suffix letter. Quint and Quart both
claim Q, so on the two numerators they share (1 and 3) they take their
distinguishing consonant — qui**N**t / qua**R**t. N and R belong to
neither the root alphabet (`H I M O Q S T`) nor the suffix alphabet
(`A E I O U Y Z`), so a three-letter code always parses unambiguously as
Q + family + peak. `-oz` takes Z because O already belongs to `-one`.

| # | Month | SH | Opens | ° | Days |
|---|-------|----|-------|---|------|
| 1 | Initia | IN | 0/1 | 0.0 | 45.7 |
| 2 | Octone | OO | 1/8 | 45.0 | 6.5 |
| 3 | Septone | SO | 1/7 | 51.4 | 8.7 |
| 4 | Hexone | HO | 1/6 | 60.0 | 12.2 |
| 5 | Quintone | QNO | 1/5 | 72.0 | 18.3 |
| 6 | Quartone | QRO | 1/4 | 90.0 | 13.0 |
| 7 | Septava | SA | 2/7 | 102.9 | 17.4 |
| 8 | Tertone | TO | 1/3 | 120.0 | 15.2 |
| 9 | Octis | OI | 3/8 | 135.0 | 9.1 |
| 10 | Quintava | QA | 2/5 | 144.0 | 10.4 |
| 11 | Septis | SI | 3/7 | 154.3 | 26.1 |
| 12 | Meridia | ME | 1/2 | 180.0 | 26.1 |
| 13 | Septyr | SY | 4/7 | 205.7 | 10.4 |
| 14 | Quintis | QNI | 3/5 | 216.0 | 9.1 |
| 15 | Octune | OU | 5/8 | 225.0 | 15.2 |
| 16 | Tertava | TA | 2/3 | 240.0 | 17.4 |
| 17 | Septune | SU | 5/7 | 257.1 | 13.0 |
| 18 | Quartis | QRI | 3/4 | 270.0 | 18.3 |
| 19 | Quintyr | QY | 4/5 | 288.0 | 12.2 |
| 20 | Hexune | HU | 5/6 | 300.0 | 8.7 |
| 21 | Septem | SE | 6/7 | 308.6 | 6.5 |
| 22 | Octoz | OZ | 7/8 | 315.0 | 45.7 |

Days are fractional, so a month draws `⌊length⌋ + 1` cells — the last one
is a partial day. Position is read off the same solstice-anchored UTC
year phase as every other timeframe, so the calendar and the year circle
are one clock; month 1 day 1 is the December solstice.

The iOS page shows all 22 months and opens focused on the current one
with today lit. The macOS widget packs the same months in reading order
with Initia pinned top-left, reflowing its column count to the tile's
width — at roughly 11 × 2 it holds the whole year.

The iOS **home-screen widget** (2 × 2 / `systemSmall`) shows one month —
whichever contains now. Elapsed days are filled, today is lit, and the
face turns over to the next month by itself when the year phase crosses
the peak. The day grid is 7 columns wide everywhere — page, board widget,
home screen — so a month keeps one shape wherever you meet it; cells size
to fit both axes and the block centers in the tile, which leaves a short
month sitting in open space rather than restyling itself. Its timeline is
the exact list of day boundaries — `start + k / 365.24219` of the year,
capped by the next month's opening — rather than a polling interval, so
it never drifts.

The two cardinal peaks are astronomical events, and posted captions name
them as such: the year peak at 0° / 180° reads Winter / Summer Solstice,
and the moon's at new / full reads New Moon / Full Moon, instead of the
generic geometry-peak label.

## Spectrum

The current chord as a vertical log-frequency rack. Each sounding tone:

```
f = (2ˢ / P) · (n / k)      bar length = amplitude
```

Per-timeframe lifts (HR 2²³ · DY 2²⁶ · QM 2²⁸ · MN/YR 2²⁹) put every
cycle in audible range without changing any pitch class. Labels show
timeframe × harmonic ("DY×7", "MN×7/3"), frequency, and whether the tone
is waxing, peaking, or waning (sign of the amplitude's derivative).

## Oscilloscope

The waveform you would hear: 30 ms of the composite signal

```
s(t) = Σᵢ Aᵢ sin(2π fᵢ t)
```

summed over all sounding tones at their current amplitudes.

## Phase Portrait

The signal plotted against its own derivative, (s, ds/dt), with the
derivative computed analytically (Σ Aᵢ ωᵢ cos ωᵢt). The topology is the
diagnostic: a **closed loop** means the active frequencies are in
small-integer ratios (a periodic chord); a **dense filled region** means
incommensurate content (quasi-periodic). Consonance becomes geometry.

## Cents Wheel

Pitch class as position on a circle:

```
angle = (1200 · log₂(f / 432)) mod 1200
```

The 12 labels sit at their just-intonation cents (not equal-tempered 30°
steps). Active tones appear as dots with a countdown to when each leaves
its fade window. Intervals between any two dots can be read directly as
arc length — this is the pure music-theory view.

## Dissonance Meters (Tenney + Entropy)

Two numbers grading all sounding pairs, amplitude-weighted:

```
Tenney:   HD = log₂(n·d) per pair, Gaussian-matched (σ = 30¢)
          to the 13-ratio JI lattice — interval complexity.
Entropy:  Shannon entropy of the lattice-identification
          distribution — interval ambiguity.
```

Meter full-scale is calibrated to the 99th percentile of a year-long
simulation; values beyond it show as spillover. Low Tenney + low entropy
together mark the clear, simple moments.

## Dissonance Graph

The same two totals as a time series over a selectable range — the
harmonic weather chart. Convergences appear as valleys (clarity), dense
clusters as ridges.

## Color Mapping

Pitch class as hue: `hue = log₂(f) mod 1` on a closed wheel
(R → Y → G → C → B → M → R). Visible light spans almost exactly one
octave, which makes the mapping unusually honest. One swatch per
timeframe (amplitude-weighted blend of its tones) plus the composite of
everything sounding.

## Harmonics Table

The static reference: every (timeframe × shape) tone with its period,
lifted frequency, nearest JI note at A = 432, and cents deviation. No date
dependency — this is the instrument's tuning chart.

## Chladni

The current tone set rendered as a vibrating plate. Each tone contributes
a standing-wave mode — m indexed by timeframe, n by harmonic number:

```
u(x, y) = Σᵢ Aᵢ sin(mᵢ π x) sin(nᵢ π y)
```

The drawn figure is the interference pattern (nodal structure) of the
whole moment — one emergent shape instead of a stack of components.

## Lissajous

Within each timeframe, every pair of sounding tones drawn as

```
x = sin(m θ),  y = sin(n θ)      m : n = the pair's frequency ratio
                                  in lowest terms (winding-aware)
```

Simple ratios give simple closed figures; the figure *is* the interval.

## Spectrogram

Harmonic activity scrolling into the past — which tones were sounding,
how strongly, over the trailing window. The system's recent history at a
glance.

## Convergence

The chord report. **NOW**: every recognized chord currently sounding —
patterns matched within ±25¢ per interval, all tones above amplitude 0.3,
at least three distinct pitch classes, with root named against A = 432
and time remaining. **UPCOMING**: the deterministic forecast — future
chord events with start, peak, and duration, computed by scanning the
schedule forward.

## Convergence Selector

The (harmonic × angle) alignment grid: background dots mark every
possible node position; cells light where geometry is currently active.
Per-timeframe or merged — the structural view of "what is lit right now"
that the chord report interprets musically.

## Calibration Result

A frozen statistical summary of a dissonance simulation run (percentiles
used to scale the meters). Multiple instances can pin different runs for
side-by-side comparison.

## Snapshot Timeline

The journal as a horizontal card strip. In Snapshot mode, clicking a card
pins **every** widget to that instant — the whole panel re-renders any
captured moment, because every view is a pure function of its timestamp.
This is the time-travel control.
