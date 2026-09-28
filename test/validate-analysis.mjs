/**
 * Cross-validation harness for the harmonic-analysis layer.
 *
 * Compares the TypeScript port against reference vectors produced by the
 * ORIGINAL Swift implementation (reference/vec-analysis -> VecAnalysis):
 *   HarmonicAnalysis.activeTones  (both the `scales:` and `assignments:` forms)
 *   DissonanceGraphRange.seconds / .label
 *   DissonanceGraphSampler.samples
 *   DissonanceCalibrator.simulate
 *
 * Run:  TZ=UTC node test/validate-analysis.mjs [vectorPath]
 *
 * Deviations are reported as the max absolute difference per field. Integers,
 * booleans and strings are compared exactly. Everything numeric is asserted at
 * 1e-9 absolute unless this header says otherwise, and every relaxation is
 * derived below rather than eyeballed.
 *
 * TOLERANCE MODEL (three documented relaxations, each counted and reported):
 *
 * 1. TIME REPRESENTATION. Swift's `Date` is a Double holding seconds; JS's is
 *    an integer count of milliseconds (ECMA-262 TimeClip truncates the time
 *    value toward zero). Two consequences:
 *      (a) A vector instant whose seconds value is not an integer is not
 *          exactly representable as a Double at these magnitudes (the ULP near
 *          1.768e9 s is ~2.4e-7 s), so Swift's Date lands on the nearest Double
 *          while JS's lands on the exact millisecond; and a fractional
 *          millisecond is truncated outright by JS. Both effects are bounded by
 *          instantGapSeconds() below. Whole-second instants are exact in both.
 *      (b) DissonanceGraphSampler's bucket instants for `.oneQuarterMoon` are
 *          637860.7192248 s / 240 apart, so they are never on the ms grid.
 *    The `hour` and `minute` timeframes are the ones that notice: their Swift
 *    degree reads Calendar's `nanosecond` component off the Double Date, so it
 *    resolves finer than the port's ms grid. A degree error reaches amplitudes
 *    through cos(...) with slope bounded by (pi/2)/(fadeFraction*cycleDuration)
 *    per second - that is exactly |d cos(x)/d t| <= |dx/dt| = (pi/2)/fadeTime.
 *    So for an affected tone the amplitude bound is
 *    (pi/2)/(0.03*cycleDuration(tf)) * instantGapSeconds(instant).
 *    For graph rows the clip propagates through a 500-term amplitude-weighted
 *    meter, so instead of chaining the bound analytically we MEASURE it: the
 *    port's own response to shifting the end instant by +/-1 ms is, per bucket,
 *    exactly that bucket's response to a 1 ms error in its own date (a shift of
 *    the end instant shifts every bucket instant by the same amount). That
 *    measured envelope is a genuine bound, not a tolerance picked to fit.
 *    Rows whose instants ARE on the ms grid are asserted at 1e-9 with no gate.
 *
 * 2. ORDER STATISTICS. DissonanceCalibrator's max/min/percentile fields are
 *    selected by value out of up to ~10^6 samples of sums over up to 561
 *    transcendental terms. The two libms disagree by a few ULP per term, so two
 *    run-adjacent order statistics can swap places; the deviation then scales
 *    with the magnitude of the statistic rather than with one term's ULP.
 *    Observed max relative deviation is 1.9e-12; these fields are asserted at
 *    max(1e-9, 1e-11 * |want|), a 5x margin that still fails any real defect.
 *
 * 3. Pure libm/ULP noise on everything else stays at 1e-9 absolute. Note this
 *    is not "free": activeTones frequencies (all date-independent closed forms)
 *    come out bit-exact, and only the cos/expo/log chains move at all.
 */

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { cycleDuration } from "../dist/core/timeFrame.js";
import * as HA from "../dist/core/harmonicAnalysis.js";
import * as DG from "../dist/core/dissonanceGraph.js";
import * as DC from "../dist/core/dissonanceCalibrator.js";

const here = dirname(fileURLToPath(import.meta.url));
const vectorPath = process.argv[2] ?? join(here, "..", "reference", "vectors-analysis.json");
const vectors = JSON.parse(readFileSync(vectorPath, "utf8"));

const FLOAT_TOL = 1e-9;
const REL_TOL = 1e-11; // calibrator order statistics - see header
const DATE_TOL_MS = 1.0; // JS TimeClip quantum - see header
const FADE_FRACTION = 0.03; // FadeMath default

const maxima = new Map();
const failures = [];
const gated = new Map(); // field -> [count, maxBound]
let checked = 0;
let ctx = "";

function bump(name, d) {
  const cur = maxima.get(name);
  if (cur === undefined || d > cur) maxima.set(name, d);
}

function gate(name, bound) {
  const g = gated.get(name) ?? [0, 0];
  g[0]++;
  if (bound > g[1]) g[1] = bound;
  gated.set(name, g);
}

function report(name, msg) {
  if (failures.length < 25) failures.push(`${ctx}${name}: ${msg}`);
}

function track(name, got, want, tol = FLOAT_TOL) {
  checked++;
  const d = Math.abs(got - want);
  bump(name, d);
  if (!(d <= tol)) {
    report(name, `got ${got} want ${want} (diff ${d.toExponential(3)}, tol ${tol.toExponential(3)})`);
    return false;
  }
  return true;
}

/** A comparison against a derived bound; counted as a gated row. */
function trackGated(name, got, want, bound) {
  checked++;
  const d = Math.abs(got - want);
  bump(name, d);
  gate(name, bound);
  if (!(d <= bound + FLOAT_TOL)) {
    report(name, `got ${got} want ${want} (diff ${d.toExponential(3)}, bound ${bound.toExponential(3)})`);
    return false;
  }
  return true;
}

function trackExact(name, got, want) {
  checked++;
  if (got !== want) {
    report(name, `got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
    return false;
  }
  return true;
}

/** One ULP of a Double at this magnitude (same approach as test/validate.mjs). */
function ulpOf(x) {
  const buf = new DataView(new ArrayBuffer(8));
  buf.setFloat64(0, x);
  const bits = buf.getBigUint64(0);
  buf.setBigUint64(0, bits + 1n);
  return buf.getFloat64(0) - x;
}

/**
 * The largest time by which the instant a vector names can differ between the
 * two Dates, in seconds.
 *
 * A whole second is an integer <= 2^53, so `ms/1000` is exactly representable
 * as a Double and both Dates hold the identical instant - gap 0. Anything with
 * a fractional second is NOT exactly representable at these magnitudes (the
 * Double ULP near 1.768e9 s is ~2.4e-7 s), so Swift's Date lands on the nearest
 * Double while JS's lands on the exact millisecond. Add JS's TimeClip
 * truncation when the named instant has a fractional millisecond.
 */
function instantGapSeconds(ms) {
  if (ms % 1000 === 0) return 0;
  const clipMs = ms - Math.trunc(ms);
  return clipMs / 1000 + ulpOf(ms / 1000) / 2;
}

function checkTones(name, got, want, gapSeconds) {
  if (!trackExact(`${name}.count`, got.length, want.length)) return;
  for (let i = 0; i < want.length; i++) {
    const g = got[i];
    const w = want[i];
    trackExact(`${name}.timeframe`, g.timeframe, w.timeframe);
    trackExact(`${name}.divisions`, g.divisions, w.divisions);
    trackExact(`${name}.skip`, g.skip, w.skip);
    trackExact(`${name}.scaling`, g.scaling, w.scaling);
    track(`${name}.frequency`, g.frequency, w.frequency);
    if (gapSeconds > 0) {
      // bound from relaxation 1: |d cos| <= (pi/2)/(0.03*cycle) * dt
      const bound = (Math.PI / 2 / (FADE_FRACTION * cycleDuration(w.timeframe))) * gapSeconds;
      trackGated(`${name}.amplitude`, g.amplitude, w.amplitude, bound);
    } else {
      track(`${name}.amplitude`, g.amplitude, w.amplitude);
    }
  }
}

// --- range tables ------------------------------------------------------------

for (const r of vectors.ranges) {
  ctx = `range(${r.range}).`;
  track("range.seconds", DG.rangeSeconds(r.range), r.seconds);
  trackExact("range.label", DG.rangeLabel(r.range), r.label);
}
ctx = "ranges.";
trackExact("ranges.allRanges.length", DG.allRanges.length, vectors.ranges.length);
for (let i = 0; i < vectors.ranges.length; i++) {
  trackExact(`ranges.allRanges[${i}]`, DG.allRanges[i], vectors.ranges[i].range);
}

// --- active tones ------------------------------------------------------------

let scalesRows = 0;
let assignRows = 0;
let totalTones = 0;
for (const r of vectors.activeTones) {
  ctx = `activeTones[${r.label}].`;
  const gapSeconds = instantGapSeconds(r.dateMs); // relaxation 1a
  const date = new Date(r.dateMs);
  let got;
  if (r.scales != null) {
    got = HA.activeTonesForScales(date, r.scales, r.threshold);
    scalesRows++;
  } else {
    got = HA.activeTones(date, r.assignments.map((a) => ({ timeframe: a.timeframe, scale: a.scale })), r.threshold);
    assignRows++;
  }
  totalTones += got.length;
  checkTones("activeTones", got, r.tones, gapSeconds);
}

// --- graph sampler -----------------------------------------------------------

let graphRows = 0;
let graphSamples = 0;
const samplerArgs = (r) => [r.range, r.includeFundamentals, r.scaling, r.bucketCount];

for (const r of vectors.graph) {
  ctx = `graph[${r.label}].`;
  const end = new Date(r.endDateMs);
  const got = DG.samples(end, ...samplerArgs(r));
  if (!trackExact("graph.sampleCount", got.length, r.samples.length)) continue;
  graphRows++;

  // Are this row's bucket instants exactly representable in both Dates? They are
  // iff the bucket step and the end instant are whole seconds (see
  // instantGapSeconds); `.oneQuarterMoon`'s 637860.7192248/240 s step never is.
  const bucketMs = (DG.rangeSeconds(r.range) / r.bucketCount) * 1000;
  const offGrid = !(bucketMs % 1 === 0 && r.endDateMs % 1000 === 0);

  // For off-grid rows, measure the port's response to a 1 ms shift of the end
  // instant: per bucket that equals its response to a 1 ms error in its own
  // date, i.e. a true bound for the DateRepresentation gap (relaxation 1b).
  let plus = null;
  let minus = null;
  if (offGrid) {
    plus = DG.samples(new Date(r.endDateMs + 1), ...samplerArgs(r));
    minus = DG.samples(new Date(r.endDateMs - 1), ...samplerArgs(r));
  }

  for (let i = 0; i < r.samples.length; i++) {
    const g = got[i];
    const w = r.samples[i];
    graphSamples++;
    if (offGrid) {
      const bT = Math.max(
        Math.abs(plus[i].tenneyNormalized - g.tenneyNormalized),
        Math.abs(minus[i].tenneyNormalized - g.tenneyNormalized),
      );
      const bE = Math.max(
        Math.abs(plus[i].entropyNormalized - g.entropyNormalized),
        Math.abs(minus[i].entropyNormalized - g.entropyNormalized),
      );
      trackGated("graph.tenneyNormalized", g.tenneyNormalized, w.tenneyNormalized, bT);
      trackGated("graph.entropyNormalized", g.entropyNormalized, w.entropyNormalized, bE);
      trackGated("graph.dateMs", g.date.getTime(), w.dateMs, DATE_TOL_MS - FLOAT_TOL);
    } else {
      track("graph.tenneyNormalized", g.tenneyNormalized, w.tenneyNormalized);
      track("graph.entropyNormalized", g.entropyNormalized, w.entropyNormalized);
      trackExact("graph.dateMs", g.date.getTime(), w.dateMs);
    }
    trackExact("graph.pairCount", g.pairCount, w.pairCount);
  }
}

// --- calibrator --------------------------------------------------------------

const STATS_FIELDS = [
  "sampleCount", "sampleIntervalSeconds", "duration",
  "totalTenneyMax", "totalTenneyP99", "totalTenneyP95", "totalTenneyMedian",
  "totalTenneyMin", "totalTenneyMean",
  "totalEntropyMax", "totalEntropyP99", "totalEntropyP95", "totalEntropyMedian",
  "totalEntropyMin", "totalEntropyMean",
  "perPairTenneyMax", "perPairTenneyP99", "perPairTenneyP95", "perPairTenneyMedian",
  "perPairEntropyMax", "perPairEntropyP99", "perPairEntropyP95", "perPairEntropyMedian",
  "activeToneCountMax", "activeToneCountMean",
];
const INT_STATS = new Set(["sampleCount", "activeToneCountMax"]);

let calibRows = 0;
for (const r of vectors.calibrator) {
  ctx = `calibrator[${r.label}].`;
  const got =
    r.label === "defaults"
      ? DC.simulate() // exercise the real default-argument path
      : DC.simulate(new Date(r.startDateMs), r.duration, r.sampleIntervalSeconds, r.scaling, r.includeFundamentals);
  calibRows++;
  for (const f of STATS_FIELDS) {
    const w = r.stats[f];
    if (INT_STATS.has(f)) {
      trackExact(`calibrator.${f}`, got[f], w);
    } else {
      // relaxation 2: order statistics scale with magnitude
      track(`calibrator.${f}`, got[f], w, Math.max(FLOAT_TOL, REL_TOL * Math.abs(w)));
    }
  }
}

// --- report ------------------------------------------------------------------

let gatedTotal = 0;
console.log(`vectors : ${vectorPath}`);
console.log(`active  : ${vectors.activeTones.length} rows (${scalesRows} scales-form, ${assignRows} assignments-form), ${totalTones} tones`);
console.log(`ranges  : ${vectors.ranges.length}   graph: ${graphRows} rows / ${graphSamples} samples   calibrator: ${calibRows} rows`);
console.log("");
console.log("max absolute deviation per field (Swift vs TypeScript):");
const sorted = [...maxima.entries()].sort((a, b) => b[1] - a[1]);
if (sorted.length === 0) console.log("  (none)");
for (const [k, v] of sorted) console.log(`  ${k.padEnd(34)} ${v.toExponential(3)}`);
console.log("");
console.log(`values checked: ${checked}`);
console.log("gated rows (asserted against a derived bound instead of 1e-9):");
if (gated.size === 0) console.log("  (none)");
for (const [k, [n, b]] of gated) {
  gatedTotal += n;
  console.log(`  ${k.padEnd(34)} ${String(n).padStart(6)} rows, max bound ${b.toExponential(3)}`);
}
console.log(`  total gated: ${gatedTotal} of ${checked} (${((100 * gatedTotal) / checked).toFixed(2)}%)`);
console.log(`  ungated numeric fields asserted at ${FLOAT_TOL.toExponential(0)} absolute;`);
console.log(`  calibrator order statistics at max(1e-9, ${REL_TOL.toExponential(0)} * |value|).`);

if (failures.length) {
  console.log(`RESULT: FAIL  (${failures.length}${failures.length >= 25 ? "+" : ""} mismatches shown, max 25)`);
  for (const f of failures) console.log(`  ${f}`);
  process.exit(1);
}
console.log(
  `RESULT: PASS  (${checked} values checked; active ${vectors.activeTones.length}, graph ${graphRows}/${graphSamples}, calibrator ${calibRows})`,
);