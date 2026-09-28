# Exochronometer — The Theory

*Time, rendered as a chord.*

Exochronometer treats nested cycles of time — year, moon, quarter moon, day,
hour, minute — as musical tones. Each cycle is a circle; each circle is a
fundamental; the polygons inscribed in it are its harmonics. The result is a
slowly evolving just-intonation chord that exists whether or not anyone is
listening, and an instrument for reading, hearing, and journaling against it.

History of changes and open questions: [DECISIONS.md](DECISIONS.md).
The instrument panel, widget by widget: [WIDGETS.md](WIDGETS.md).

---

## 1 · Cycles are tones

A cycle with period **P** is a tone with frequency **f = 1/P**. Multiplying
by powers of 2 (octave lifting) moves a tone into the audible band while
preserving every interval exactly — pitch class is invariant under octave
shift, so the harmony between cycles is real, not an artifact of scaling.

| Cycle | Period | Natural frequency | Lifted (merged view) |
|---|---|---|---|
| Year | 365.24219 d (mean tropical) | 3.169 × 10⁻⁸ Hz | ×2²⁹ → 17.0 Hz |
| Moon | 29.530589 d (synodic) | 3.919 × 10⁻⁷ Hz | ×2²⁹ → 210.4 Hz |
| Quarter moon | synodic ÷ 4 | 1.568 × 10⁻⁶ Hz | ×2²⁸ → 420.8 Hz |
| Day | 86,400 s | 1.157 × 10⁻⁵ Hz | ×2²⁶ → 776.7 Hz |
| Hour | 3,600 s | 2.778 × 10⁻⁴ Hz | ×2²³ → 2330.2 Hz |
| Minute | 60 s | 1.667 × 10⁻² Hz | (display only) |

---

## 2 · Geometry is harmonics

Inscribe a polygon in a circle and you have drawn a harmonic. A triangle
completes three times per rotation — the 3rd harmonic. A pentagon, the 5th.
The shapes used are every {n/k} polygon for n = 3…8 with gcd(n, k) = 1:

```
{3/1} {4/1} {5/1} {5/2} {6/1} {7/1} {7/2} {7/3} {8/1} {8/3}
```

A **regular** polygon {n/1} is the integer harmonic n·f. A **star** polygon
{n/k} winds through its n vertices over k rotations, giving frequency
(n/k)·f — a *rational* partial. Stars with k = 2 are exact octaves of their
regular polygon; stars with k = 3 are not (ratio 3 = octave + fifth), and
contribute the only two pitch classes the integer series lacks:

| Shape | Frequency | Pitch class | Interval |
|---|---|---|---|
| {7/3} heptagram | (7/3)·f | 7/6 | septimal minor third (266.9¢) |
| {8/3} octagram | (8/3)·f | 4/3 | perfect fourth (498.0¢) |

A harmonic sounds when the indicator approaches a vertex its winding path
visits this rotation: amplitude is a cosine fade over the approach,
peaking at 1.0 on the vertex. Each tone is audible for 6% × (n/k) of its
cycle — the sky has weather.

---

## 3 · The fixed chord of civil time

The civil units stand in exact integer ratios — 24 hours, 60 minutes — and
exact integer ratios are exact musical intervals. The clock on the wall is
a chord, and has been all along:

| Pair | Ratio | Reduced | Interval | Cents |
|---|---|---|---|---|
| hour : day | 24 | 3/2 | **perfect fifth** | 701.955 (exact) |
| minute : hour | 60 | 15/8 | **major seventh** | 1088.269 (exact) |
| minute : day | 1440 | 45/32 | **tritone** | 590.224 (exact) |

With day = C: the hour is G, the minute is F♯ — eternally, by arithmetic,
not by tuning. These intervals cannot drift, ever.

---

## 4 · The drifting sky

The astronomical cycles refuse to lock. The year and the moon are
incommensurate with the civil chord and with each other — that
incommensurability is why calendars are hard, and it is also what makes
the system *move*:

| Pair | Pitch-class interval | Nearest simple ratio |
|---|---|---|
| year : day | ≈ 615.4¢ | 10/7 (617.5¢) — within 2¢, coincidence |
| moon : day | ≈ 1060.9¢ | between 11/6 and 13/7 — permanently ambiguous |
| moon : quarter moon | 0¢ (exact 4:1) | unison class — one voice, two octaves |

The full picture: **a crystalline civil chord (C–G–F♯) with two
astronomical tones drifting through it.** Every convergence the instrument
detects is a moment when the drifting voices align with the fixed ones.

---

## 5 · The grand zero

Every phase in the system is anchored to one instant — the **meeting of
sun and moon** of December 2014:

```
December solstice   2014-12-21  23:03 UTC   →  year phase 0°
New moon            2014-12-22  01:36 UTC   →  moon phase 0°
                                Δ = 2.5 hours
```

A solstice is the same instant for every observer on Earth — unlike
midnight, it needs no meridian. The sun–moon meeting recurs on the 19-year
Metonic cycle (235 lunations ≈ 19 tropical years): 1995 → 2014 → 2033. The
instrument's zero is itself one of the deepest near-commensurabilities in
the sky. The year advances from the solstice by the mean tropical year;
Jan 1 sits ~10° into the cycle. All phases are computed in UTC: everyone
on Earth sees the same geometry at the same instant, because everyone is
at the same location in time.

---

## 6 · Fundamentals are linear time

The fundamentals never change — amplitude 1.0, always on. They are the
metronome: linear time itself. The overtones come and go with the
geometry: they are the structure of *this* moment. Disable the
fundamentals and the question becomes:

> with the steady ticking stripped away, what shape does this moment have?

That remainder is the exo-content, and it is what every analytical view
measures by default.

---

## 7 · Measuring the moment

Two complementary numbers grade each pair of sounding tones, both computed
against a 13-ratio just-intonation lattice (5-limit plus the harmonic 7th):

**Tenney harmonic distance** — *how complex is this interval?*

```
HD = log₂(n · d)        for the ratio n:d in lowest terms

unison 1:1 → 0     fifth 3:2 → 2.58     third 5:4 → 4.32     tritone 45:32 → 10.49
```

**Harmonic entropy** — *how clearly is it one interval and not another?*
Each pair's cents value is smeared by a Gaussian (σ = 30¢) over the lattice;
the Shannon entropy of that identification distribution is low when the
interval is unmistakably one ratio, high when it sits between identities.

Low HD + low entropy = a clear, simple interval: consonance you can point
at. The meters are calibrated against a year-long simulation (99th
percentile = full scale). Both are pure ratio mathematics — no model of
the ear, no biology.

---

## 8 · Chords and convergences

A chord is detected when every interval of a known pattern (triads and
tetrads, just-intonation voicings) lands within ±25¢ — perceptibly
stretched but recognizable. A chord requires **at least three distinct
pitch classes**; two pitch classes is an interval in chord costume.

Because the entire system is deterministic, convergences can be computed
*forward*: the projector scans the future and lists upcoming chords with
their start, peak, and duration — a weather forecast for harmony. Chords
spanning multiple timeframes are the interesting ones: a moment when the
moon's heptagram, the day's pentagon, and the hour's triangle agree on a
minor triad is a meeting of three otherwise unrelated clocks.

---

## 9 · Phase-indexed memory

A journal note is stamped not just with a timestamp but with its **angular
position on every circle at once**. Strip away linear time and the note
participates in every future return of its phases — it recurs, as an echo,
whenever any of its cycles comes back around.

Everything else in a snapshot — degrees, harmonics, chords, meters — is a
pure function of the timestamp. The machine is reproducible clockwork;
**the only information in the system is what a person adds to it.** The
note is the signal. The geometry is the indexing scheme.

---

## 10 · The conjectures

The instrument is the established part. These are the open claims it
exists to test, ordered by testability:

- **C1 — Injection recurrence.** A large public event at phase θ produces
  above-baseline *semantic* recurrence at harmonic returns of θ
  (the 3rd–8th-harmonic node positions of later rotations). Testable
  against timestamped public corpora with sham-window controls; the
  non-trivial harmonics matter, since nobody commemorates one-fifth of a
  year.
- **C2 — Phase-indexed personal recurrence.** One person's notes written
  at harmonically related phases are more semantically similar than
  routine (time-of-day, weekday, season) explains.
- **C3 — Convergence salience.** Moments of high cross-timeframe
  consonance feel different — testable with blind prompts at real vs.
  sham convergence times, rated before seeing the meters.
- **C4 — Bidirectional transfer.** Information placed at a node is
  available at *earlier* traversals of related nodes. Not yet
  operationalized: as built, forward structure is the schedule, so any
  honest test must show an effect the schedule alone cannot produce.

If all four fail, what remains is an instrument: a just-intonation
rendering of nested time with a genuinely beautiful fixed structure.
That outcome is acceptable, and was worth building either way.

---

## 11 · Design choices

The honest list of free parameters. The system's "moments" are functions
of these knobs; none of them are discoveries.

| Knob | Value | Note |
|---|---|---|
| Harmonic range | n = 3…8 | legibility cap, expandable |
| Fade window | ±10.8° (3% of cycle) | ≈ 2 min of peak geometry on the hour circle |
| JI lattice | 13 ratios, 5-limit + 7/4 | shared by all metrics and labels |
| Ratio-snap σ | 30¢ | forgiving JI |
| Chord tolerance | ±25¢ per interval | recognizably-that-chord threshold |
| Chord amplitude gate | 0.3 | |
| Pitch anchor | A = 432 Hz | naming only — every metric is interval-relative |
| Phase anchors | UTC; year = December solstice | global synchrony is a core commitment |
| Epoch | 2014-12-22 01:36 UTC new moon | the Metonic grand zero |

---

## 12 · Glossary

- **Fundamental** — the always-on tone of a cycle; linear time.
- **Overtone / harmonic** — the tone of an inscribed shape; the exo-content.
- **Winding tone** — a star polygon {n/k} sounding at (n/k)·f.
- **Node** — a polygon vertex; a phase where a harmonic activates.
- **Convergence** — multiple shapes or timeframes simultaneously active in
  clean interval relation.
- **Exoconcatenation** — linking events by shared harmonic phase rather
  than linear-time adjacency.
- **Injection** — any event that shapes the collective semantic substrate.
- **Grand zero** — the 2014 solstice/new-moon epoch all phases anchor to.
