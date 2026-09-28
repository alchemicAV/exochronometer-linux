/**
 * Cross-validation harness for the dissonance/voicing layer.
 *
 * Compares the TypeScript port against reference vectors produced by the
 * ORIGINAL Swift implementation (reference/vec-dissonance -> VecDissonance).
 *
 * Run:  TZ=UTC node test/validate-dissonance.mjs
 *
 * Deviations are reported as the max absolute difference per field. Every
 * field is checked at 1e-9 unless noted; integers, booleans and strings are
 * compared exactly. Swift's JSONEncoder OMITS nil optionals rather than
 * emitting null, so absent keys are compared with `x == null`.
 */

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import * as Chord from "../dist/core/chordCatalog.js";
import * as DM from "../dist/core/dissonanceMath.js";
import { isLoopClosed, defaultTolerance } from "../dist/core/phasePortraitMath.js";
import * as Synth from "../dist/core/synthParams.js";

const here = dirname(fileURLToPath(import.meta.url));
const vectorPath = process.argv[2] ?? join(here, "..", "reference", "vectors-dissonance.json");
const vectors = JSON.parse(readFileSync(vectorPath, "utf8"));

// 1e-9 absolute. Both sides compute the same closed-form expressions over the
// SAME doubles (the JSON round-trips to the identical bit pattern), but the
// transcendental calls go through different libms: Swift/Foundation uses the
// system libm, while V8 uses its own ports of fdlibm's log/log2/exp. Those
// can differ by ~1 ULP (~1e-16 relative), and pairTenney/pairEntropy sum 13
// such terms, so the honest floor is a few times 1e-15 for values of order 1
// and ~1e-12 for the largest Tenney totals (~150). 1e-9 is therefore
// comfortably above the ULP noise while still being ~6 orders of magnitude
// tighter than the tolerances used elsewhere in this repo.
const FLOAT_TOL = 1e-9;

const maxima = new Map();
const failures = [];
let checked = 0;

function track(name, got, want, tol = FLOAT_TOL) {
  checked++;
  const d = Math.abs(got - want);
  const cur = maxima.get(name);
  if (cur === undefined || d > cur) maxima.set(name, d);
  if (!(d <= tol)) {
    if (failures.length < 20) {
      failures.push(`${name}: got ${got} want ${want} (diff ${d.toExponential(3)})`);
    }
    return false;
  }
  return true;
}

function trackStr(name, got, want) {
  checked++;
  if (got !== want) {
    if (failures.length < 20) failures.push(`${name}: got "${got}" want "${want}"`);
    return false;
  }
  return true;
}

function trackBool(name, got, want) {
  checked++;
  if (got !== want) {
    if (failures.length < 20) failures.push(`${name}: got ${got} want ${want}`);
    return false;
  }
  return true;
}

// --- chord tables ------------------------------------------------------------

function checkChords(label, got, want) {
  trackBool(`${label}.length`, got.length, want.length);
  const n = Math.min(got.length, want.length);
  for (let i = 0; i < n; i++) {
    const g = got[i];
    const w = want[i];
    trackStr(`${label}[${i}].name`, g.name, w.name);
    trackStr(`${label}[${i}].abbr`, g.abbreviation, w.abbr);
    track(`${label}[${i}].toneCount`, Chord.toneCount(g), w.toneCount, 0);
    trackBool(`${label}[${i}].intervals.length`, g.intervals.length, w.intervals.length);
    const m = Math.min(g.intervals.length, w.intervals.length);
    for (let k = 0; k < m; k++) {
      track(`${label}[${i}].intervals[${k}]`, g.intervals[k], w.intervals[k]);
    }
  }
}

checkChords("chordIntervals", Chord.intervals, vectors.chordIntervals);
checkChords("chordTriads", Chord.triads, vectors.chordTriads);
checkChords("chordTetrads", Chord.tetrads, vectors.chordTetrads);
checkChords("chordAll", Chord.all, vectors.chordAll);
checkChords("chordChords", Chord.chords, vectors.chordChords);

// --- JI ratio table ----------------------------------------------------------

trackBool("jiRatios.length", DM.jiRatios.length, vectors.jiRatios.length);
for (let i = 0; i < vectors.jiRatios.length; i++) {
  const w = vectors.jiRatios[i];
  const g = DM.jiRatios[i];
  if (!g) { trackBool(`jiRatios[${i}]`, false, true); continue; }
  track(`jiRatios[${i}].n`, g.n, w.n, 0);
  track(`jiRatios[${i}].d`, g.d, w.d, 0);
}

// --- per-pair sweep ----------------------------------------------------------

let pairChecked = 0;
for (const r of vectors.pairs) {
  track(`pairTenney(${r.sigma})`, DM.pairTenney(r.cents, r.sigma), r.tenney);
  track(`pairEntropy(${r.sigma})`, DM.pairEntropy(r.cents, r.sigma), r.entropy);
  pairChecked++;
}

// --- totals over tone sets ---------------------------------------------------

function toTones(rows) {
  return rows.map((t) => ({
    timeframe: t.timeframe,
    divisions: t.divisions,
    skip: t.skip,
    scaling: t.scaling,
    frequency: t.frequency,
    amplitude: t.amplitude,
  }));
}

let totalChecked = 0;
for (const r of vectors.totals) {
  const tones = toTones(r.tones);
  track(`totalTenney[${r.label}]`, DM.totalTenney(tones), r.tenney);
  track(`totalEntropy[${r.label}]`, DM.totalEntropy(tones), r.entropy);
  totalChecked++;
}

// --- phase-portrait loop closure --------------------------------------------

let loopChecked = 0;
for (const r of vectors.loops) {
  const tones = toTones(r.tones);
  // r.tol is ABSENT (not null) when Swift used the default argument.
  const got = r.tol == null ? isLoopClosed(tones, r.window) : isLoopClosed(tones, r.window, r.tol);
  trackBool(`isLoopClosed[${r.label}]`, got, r.closed);
  loopChecked++;
}
track("defaultTolerance", defaultTolerance, 0.05, 0);

// --- calibration constants ---------------------------------------------------

track("calibration.tenneyMeterMax", DM.tenneyMeterMax, vectors.calibration.tenneyMeterMax, 0);
track("calibration.entropyMeterMax", DM.entropyMeterMax, vectors.calibration.entropyMeterMax, 0);
track("calibration.spilloverDisplayCap", DM.spilloverDisplayCap, vectors.calibration.spilloverDisplayCap, 0);

// --- synth params ------------------------------------------------------------

const SYNTH_FIELDS = [
  "attackMs", "releaseMs", "lowpassHz", "reverbMix", "reverbPreset",
  "tremoloRateHz", "tremoloDepth", "width", "unisonVoices",
  "detuneCents", "enrichment", "partials", "partialTilt",
];

function checkSynthRow(label, got, want) {
  for (const f of SYNTH_FIELDS) {
    track(`${label}.${f}`, got[f], want[f], 0);
  }
}

const defaults = Synth.makeSynthParams();
checkSynthRow("synthDefaults", defaults, vectors.synthDefaults);
checkSynthRow("synthSafePad", Synth.safePad, vectors.synthSafePad);

// safePad is `static let safePad = SynthParams()`
checkSynthRow("synthSafePadEqDefaults", Synth.safePad, vectors.synthDefaults);

const reset = Synth.resetTimbre(Synth.makeSynthParams());
checkSynthRow("synthResetTimbre", reset, vectors.synthResetTimbre);

trackBool("reverbPresetNames.length", Synth.reverbPresetNames.length, vectors.reverbPresetNames.length);
for (let i = 0; i < vectors.reverbPresetNames.length; i++) {
  trackStr(`reverbPresetNames[${i}]`, Synth.reverbPresetNames[i], vectors.reverbPresetNames[i]);
}

const preset = Synth.makeSynthPreset(
  vectors.preset.name,
  Synth.makeSynthParams(),
  vectors.preset.id,
  new Date(vectors.preset.savedAtMs),
);
trackStr("preset.id", preset.id, vectors.preset.id);
trackStr("preset.name", preset.name, vectors.preset.name);
track("preset.savedAtMs", preset.savedAt.getTime(), vectors.preset.savedAtMs, 0);
checkSynthRow("preset.params", preset.params, vectors.preset.params);

// --- report ------------------------------------------------------------------

console.log(`vectors : ${vectorPath}`);
console.log(`pairs   : ${pairChecked}   totals: ${totalChecked}   loops: ${loopChecked}`);
console.log(`synth   : 3 param rows x ${SYNTH_FIELDS.length} fields + ${vectors.reverbPresetNames.length} preset names`);
console.log("");
console.log("max absolute deviation per field (Swift vs TypeScript):");
const sorted = [...maxima.entries()].sort((a, b) => b[1] - a[1]);
if (sorted.length === 0) console.log("  (none)");
for (const [k, v] of sorted) console.log(`  ${k.padEnd(34)} ${v.toExponential(3)}`);
console.log("");
console.log(`values checked: ${checked}`);

if (failures.length) {
  console.log(`RESULT: FAIL  (${failures.length}${failures.length >= 20 ? "+" : ""} mismatches shown, max 20)`);
  for (const f of failures) console.log(`  ${f}`);
  process.exit(1);
}
console.log(`RESULT: PASS  (${checked} values checked; pairs ${pairChecked}, totals ${totalChecked}, loops ${loopChecked}, all within ${FLOAT_TOL.toExponential(0)} absolute)`);
