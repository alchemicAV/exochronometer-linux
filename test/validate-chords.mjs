/**
 * Cross-validation harness for the chord layer (ChordDetector + ChordProjector).
 *
 * Compares the TypeScript port against reference vectors produced by the
 * ORIGINAL Swift implementation (reference/vec-chords -> VecChords).
 *
 * Run:  TZ=UTC node test/validate-chords.mjs
 *       (optional argv[2] overrides the vector path)
 *
 * METHOD
 *  - Numeric fields are checked at 1e-9 absolute (see FLOAT_TOL below).
 *    Integers, booleans and strings are compared exactly.
 *  - Swift's JSONEncoder OMITS nil optionals rather than emitting null, so
 *    absent keys are compared with `x == null`.
 *  - IDENTITY, NOT JUST SCORE: ChordMatch and ChordEvent both carry a
 *    Hashable-derived `id`. Every match / event is compared *by that id*
 *    (tone lists canonicalised into tone-id order), so selecting a different
 *    but equally-scoring tone subset fails even when fitCents agree exactly.
 *
 * ORDERING (the one thing that is genuinely implementation-defined in Swift)
 *  ChordDetector.detect's final step is
 *      bestPerSignature.values.sorted { $0.fitCents < $1.fitCents }
 *  where `bestPerSignature` is a Swift **Dictionary** (unordered iteration)
 *  and `sorted(by:)` is introsort (**not stable**). When several matches share
 *  the exact same fitCents, the Swift output order is therefore arbitrary.
 *  This port keeps Swift's `Map` insertion order and uses JS `Array#sort`
 *  (stable), which is a faithful *choice* among equally valid orders.
 *  The harness therefore:
 *    - always asserts the returned multiset by (fitCents, id), and
 *    - additionally asserts the raw emitted order whenever every fitCents /
 *      startMs in a row is distinct (then the Swift sort is a total order and
 *      the output order IS well defined).
 *  Tied rows are gated from the raw-order assertion only, counted and printed.
 */

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import * as Chord from "../dist/core/chordCatalog.js";
import * as CD from "../dist/core/chordDetector.js";
import * as CP from "../dist/core/chordProjector.js";

const here = dirname(fileURLToPath(import.meta.url));
const vectorPath = process.argv[2] ?? join(here, "..", "reference", "vectors-chords.json");
const vectors = JSON.parse(readFileSync(vectorPath, "utf8"));

// 1e-9 absolute. Both sides compute the same closed-form expressions over the
// SAME doubles (the JSON round-trips to the identical bit pattern), and a fit
// is a sum of at most 6 such terms, so most fields agree to 0 or ~1 ULP.
//
// The largest observed deviation (~1e-11, on amplitudes and on
// peakAmplitudeProduct) is NOT a porting defect: see the MEASURED FLOOR note in
// the report. It comes from timeFrame's quarterMoonDegree, which computes
// `(elapsed/quarterMoonSeconds - floor(...)) * 360` — by the 2026 dates that
// fractional part is the tail of a ~545-cycle count, so the subtraction loses
// ~3 digits and the resulting degree differs between libms by ~1e-10 degrees.
// nodeActivation turns a degree into `cos(delta/fadeTime * pi/2)`, which scales
// that up to ~1e-11 in the amplitude. 1e-9 sits ~100x above that honest floor
// and is still ~4 orders of magnitude tighter than the ±25¢ tolerance the
// algorithm itself uses - it is NOT widened to hide a defect.
const FLOAT_TOL = 1e-9;

const maxima = new Map();
const failures = [];
let checked = 0;
let identityMismatches = 0;
let orderGated = 0;      // rows skipped from the raw-order assertion (tied keys)
let orderAsserted = 0;   // rows where the raw order was also asserted
let canonicalLists = 0;  // tone / match / event lists compared by identity

function track(group, ctx, got, want, tol = FLOAT_TOL) {
  checked++;
  const d = Math.abs(got - want);
  if (Number.isFinite(d)) {
    const cur = maxima.get(group);
    if (cur === undefined || d > cur) maxima.set(group, d);
  }
  if (!(d <= tol)) {
    if (failures.length < 30) {
      failures.push(`${group} ${ctx}: got ${got} want ${want} (diff ${Number.isFinite(d) ? d.toExponential(3) : d})`);
    }
    return false;
  }
  return true;
}

function trackStr(group, ctx, got, want) {
  checked++;
  const ok = got === want;
  if (!ok) {
    if (failures.length < 30) failures.push(`${group} ${ctx}: got "${got}" want "${want}"`);
    return false;
  }
  return true;
}

// --- helpers -----------------------------------------------------------------

function toTones(rows) {
  return (rows ?? []).map((t) => ({
    timeframe: t.timeframe,
    divisions: t.divisions,
    skip: t.skip,
    scaling: t.scaling,
    frequency: t.frequency,
    amplitude: t.amplitude,
  }));
}

function patternByAbbr(abbr) {
  const p = Chord.all.find((x) => x.abbreviation === abbr);
  if (!p) throw new Error(`unknown pattern abbreviation ${abbr}`);
  return p;
}

function patternsByAbbrs(abbrs) {
  return abbrs.map(patternByAbbr);
}

/** Swift's HarmonicTone.id - the tone's identity under Hashable. */
function toneId(t) {
  return `${t.timeframe}-${t.divisions}/${t.skip}-${t.scaling}`;
}

function byId(a, b) {
  const x = toneId(a);
  const y = toneId(b);
  return x < y ? -1 : x > y ? 1 : 0;
}

function cmp(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

/**
 * Compare two tone lists as id-keyed identities. Lists are canonicalised into
 * tone-id order first; each element is then matched by its id and every field
 * compared. An id that differs is an identity failure and its fields are not
 * compared (they belong to different tones).
 */
function compareTones(group, ctx, got, want) {
  checked++;
  track(group.replace(/\.frequency$/, ".length"), ctx, got.length, want.length, 0);
  const g = [...got].sort(byId);
  const w = [...want].sort(byId);
  canonicalLists++;
  const n = Math.min(g.length, w.length);
  for (let i = 0; i < n; i++) {
    if (g[i] === undefined || w[i] === undefined) continue;
    if (toneId(g[i]) !== toneId(w[i])) {
      identityMismatches++;
      if (failures.length < 30) {
        failures.push(`${group} ${ctx}[${i}].id: got "${toneId(g[i])}" want "${toneId(w[i])}"`);
      }
      continue;
    }
    track(`${group}.divisions`, `${ctx}[${i}]`, g[i].divisions, w[i].divisions, 0);
    track(`${group}.skip`, `${ctx}[${i}]`, g[i].skip, w[i].skip, 0);
    track(`${group}.scaling`, `${ctx}[${i}]`, g[i].scaling, w[i].scaling, 0);
    track(`${group}.frequency`, `${ctx}[${i}]`, g[i].frequency, w[i].frequency);
    track(`${group}.amplitude`, `${ctx}[${i}]`, g[i].amplitude, w[i].amplitude);
  }
}

/** Compare one ChordMatch against a vector MatchRow. */
function compareMatch(ctx, got, want, section = "match") {
  checked++;
  if (want == null) {
    if (got != null) {
      identityMismatches++;
      if (failures.length < 30) failures.push(`${section}.id ${ctx}: got ${CD.chordMatchId(got)} want none`);
    }
    return;
  }
  if (got == null) {
    identityMismatches++;
    if (failures.length < 30) failures.push(`${section}.id ${ctx}: got none want ${want.id}`);
    return;
  }
  if (CD.chordMatchId(got) !== want.id) {
    identityMismatches++;
    if (failures.length < 30) failures.push(`${section}.id ${ctx}: got ${CD.chordMatchId(got)} want ${want.id}`);
    return;
  }
  trackStr(`${section}.abbr`, ctx, got.pattern.abbreviation, want.abbr);
  track(`${section}.fitCents`, ctx, got.fitCents, want.fitCents);
  compareTones(`${section}.tones`, ctx, got.tones, toTones(want.tones));
}

/**
 * Compare a ChordMatch list. Canonical order key: (fitCents, id). The raw
 * emitted order is asserted too when every fitCents is distinct.
 */
function compareMatchList(section, ctx, got, want) {
  track(`${section}.count`, ctx, got.length, want.length, 0);
  const canon = (list, idOf, fitOf) =>
    [...list].sort((a, b) => fitOf(a) - fitOf(b) || cmp(idOf(a), idOf(b)));
  const g = canon(got, CD.chordMatchId, (m) => m.fitCents);
  const w = canon(want, (m) => m.id, (m) => m.fitCents);
  canonicalLists++;
  const n = Math.min(g.length, w.length);
  for (let i = 0; i < n; i++) compareMatch(`${ctx}/${section}[${i}]`, g[i], w[i], section);

  const fits = want.map((m) => m.fitCents);
  if (new Set(fits).size === fits.length) {
    orderAsserted++;
    const gi = got.map(CD.chordMatchId);
    const wi = want.map((m) => m.id);
    for (let i = 0; i < Math.min(gi.length, wi.length); i++) {
      trackStr(`${section}.order.id`, `${ctx}[${i}]`, gi[i], wi[i]);
    }
  } else {
    orderGated++;
  }
}

// --- pitch class signatures --------------------------------------------------

let sigChecked = 0;
for (const r of vectors.signatures) {
  const got = CD.pitchClassSignature(toTones(r.tones), patternByAbbr(r.abbr));
  trackStr("signature", `${r.label}/${r.abbr}`, got, r.signature);
  sigChecked++;
}

// --- match -------------------------------------------------------------------

let matchChecked = 0;
let matchNil = 0;
for (const r of vectors.matchCases) {
  const got = CD.match(toTones(r.tones), patternByAbbr(r.abbr), r.tolerance);
  compareMatch(`${r.label}/${r.abbr}/tol${r.tolerance}`, got, r.result);
  if (r.result == null) matchNil++;
  matchChecked++;
}

// --- detect ------------------------------------------------------------------

let detectChecked = 0;
let detectEmpty = 0;
for (const r of vectors.detectCases) {
  const got = CD.detect(toTones(r.tones), r.ampThreshold, patternsByAbbrs(r.patternAbbrs));
  compareMatchList("detect", `${r.label}/amp${r.ampThreshold}/${r.patternAbbrs.length}pat`, got, r.matches);
  if (r.matches.length === 0) detectEmpty++;
  detectChecked++;
}

// --- current -----------------------------------------------------------------

let currentChecked = 0;
for (const r of vectors.currentCases) {
  const got = CP.current(
    new Date(r.ms),
    r.ampThreshold,
    r.scaling,
    r.includeFundamentals,
    r.crossTimeframeOnly,
    r.excludeHourly,
    patternsByAbbrs(r.patternAbbrs),
  );
  const ctx = `${r.ms}/s${r.scaling}/a${r.ampThreshold}/f${r.includeFundamentals ? 1 : 0}` +
    `x${r.crossTimeframeOnly ? 1 : 0}h${r.excludeHourly ? 1 : 0}/${r.patternAbbrs.length}pat`;
  compareMatchList("current", ctx, got, r.matches);
  currentChecked++;
}

// --- candidateChords ---------------------------------------------------------

let candidateChecked = 0;
let candidateTotal = 0;
for (const r of vectors.candidateCases) {
  const got = CP.candidateChords(
    r.scaling,
    patternsByAbbrs(r.patternAbbrs),
    r.tolerance,
    r.includeFundamentals,
    r.crossTimeframeOnly,
    r.excludeHourly,
  );
  const ctx = `s${r.scaling}/tol${r.tolerance}/f${r.includeFundamentals ? 1 : 0}` +
    `x${r.crossTimeframeOnly ? 1 : 0}h${r.excludeHourly ? 1 : 0}/${r.patternAbbrs.length}pat`;
  track("candidateChords.count", ctx, got.length, r.candidates.length, 0);
  // candidateChords is a deterministic single-threaded enumeration (no
  // Dictionary is iterated), so the ORDER is part of the contract here.
  const n = Math.min(got.length, r.candidates.length);
  for (let i = 0; i < n; i++) {
    trackStr("candidateChords.abbr", `${ctx}[${i}]`, got[i].pattern.abbreviation, r.candidates[i].abbr);
    track("candidateChords.fitCents", `${ctx}[${i}]`, got[i].fitCents, r.candidates[i].fitCents);
    compareTones("candidateChords.tones", `${ctx}[${i}]`, got[i].tones, toTones(r.candidates[i].tones));
  }
  candidateTotal += r.candidates.length;
  candidateChecked++;
}

// --- upcoming ----------------------------------------------------------------

const SIG_FIELDS = ["timeframe", "divisions", "skip", "divisionLabel"];

let upcomingChecked = 0;
let upcomingEvents = 0;
let upcomingEmpty = 0;

for (const r of vectors.upcomingCases) {
  const got = CP.upcoming(
    new Date(r.fromMs),
    r.lookahead,
    r.ampThreshold,
    r.sampleInterval,
    r.scaling,
    r.includeFundamentals,
    r.crossTimeframeOnly,
    r.excludeHourly,
    r.excludeCurrentlyActive,
    patternsByAbbrs(r.patternAbbrs),
    r.maxResults,
  );
  const ctx = `${r.fromMs}/la${r.lookahead}/si${r.sampleInterval}/s${r.scaling}` +
    `/a${r.ampThreshold}/f${r.includeFundamentals ? 1 : 0}x${r.crossTimeframeOnly ? 1 : 0}` +
    `h${r.excludeHourly ? 1 : 0}/e${r.excludeCurrentlyActive ? 1 : 0}/mr${r.maxResults}` +
    `/${r.patternAbbrs.length}pat`;

  const rows = got.map((e) => ({
    id: CP.chordEventId(e),
    abbr: e.pattern.abbreviation,
    toneSignature: e.toneSignature.map((s) => ({
      timeframe: s.timeframe,
      divisions: s.divisions,
      skip: s.skip,
      divisionLabel: CP.toneSignatureLabel(s),
    })),
    startMs: e.startTime.getTime(),
    peakMs: e.peakTime.getTime(),
    endMs: e.endTime.getTime(),
    fitCents: e.fitCents,
    peakAmplitudeProduct: e.peakAmplitudeProduct,
  }));

  track("upcoming.count", ctx, rows.length, r.events.length, 0);
  if (r.events.length === 0) upcomingEmpty++;

  // Canonical identity order: (startMs, id).
  const key = (e) => `${e.startMs}|${e.id}`;
  const g = [...rows].sort((a, b) => cmp(key(a), key(b)));
  const w = [...r.events].sort((a, b) => cmp(key(a), key(b)));
  canonicalLists++;

  const n = Math.min(g.length, w.length);
  for (let i = 0; i < n; i++) {
    const gr = g[i];
    const wr = w[i];
    if (gr.id !== wr.id) {
      identityMismatches++;
      if (failures.length < 30) failures.push(`upcoming ${ctx}[${i}].id: got ${gr.id} want ${wr.id}`);
      continue;
    }
    trackStr("upcoming.abbr", `${ctx}/${gr.id}`, gr.abbr, wr.abbr);
    track("upcoming.startMs", `${ctx}/${gr.id}`, gr.startMs, wr.startMs, 0);
    track("upcoming.peakMs", `${ctx}/${gr.id}`, gr.peakMs, wr.peakMs, 0);
    track("upcoming.endMs", `${ctx}/${gr.id}`, gr.endMs, wr.endMs, 0);
    track("upcoming.fitCents", `${ctx}/${gr.id}`, gr.fitCents, wr.fitCents);
    track("upcoming.peakAmplitudeProduct", `${ctx}/${gr.id}`, gr.peakAmplitudeProduct, wr.peakAmplitudeProduct);
    track("upcoming.toneSignature.length", `${ctx}/${gr.id}`, gr.toneSignature.length, wr.toneSignature.length, 0);
    const m = Math.min(gr.toneSignature.length, wr.toneSignature.length);
    for (let k = 0; k < m; k++) {
      const gs = gr.toneSignature[k];
      const ws = wr.toneSignature[k];
      for (const f of SIG_FIELDS) {
        const gname = `upcoming.toneSignature.${f}`;
        if (f === "timeframe" || f === "divisionLabel") {
          trackStr(gname, `${ctx}/${gr.id}[${k}]`, gs[f], ws[f]);
        } else {
          track(gname, `${ctx}/${gr.id}[${k}]`, gs[f], ws[f], 0);
        }
      }
    }
  }

  // Raw-order assertion only when every startMs is distinct (see ORDERING note).
  const starts = r.events.map((e) => e.startMs);
  if (new Set(starts).size === starts.length) {
    orderAsserted++;
    for (let i = 0; i < Math.min(rows.length, r.events.length); i++) {
      trackStr("upcoming.order.id", `${ctx}[${i}]`, rows[i].id, r.events[i].id);
    }
  } else {
    orderGated++;
  }

  upcomingEvents += r.events.length;
  upcomingChecked++;
}

// --- report ------------------------------------------------------------------

console.log(`vectors : ${vectorPath}`);
console.log(`signatures ${sigChecked}   match ${matchChecked} (nil ${matchNil})   detect ${detectChecked} (empty ${detectEmpty})`);
console.log(`current ${currentChecked}   candidateChords ${candidateChecked} (${candidateTotal} candidates)   upcoming ${upcomingChecked} (${upcomingEvents} events, empty ${upcomingEmpty})`);
console.log(`identity-ordered lists compared: ${canonicalLists}`);
console.log(`raw-order asserted: ${orderAsserted} rows   gated as tied/ambiguous: ${orderGated} rows`);
console.log("");
console.log("max absolute deviation per field (Swift vs TypeScript):");
const sorted = [...maxima.entries()].sort((a, b) => b[1] - a[1]);
if (sorted.length === 0) console.log("  (none)");
for (const [k, v] of sorted) console.log(`  ${k.padEnd(42)} ${v.toExponential(3)}`);
console.log("");
console.log(`values checked: ${checked}`);
console.log(`identity mismatches: ${identityMismatches}`);

if (failures.length || identityMismatches) {
  console.log(`RESULT: FAIL  (${failures.length}${failures.length >= 30 ? "+" : ""} mismatches shown, max 30; ${identityMismatches} identity mismatches)`);
  for (const f of failures) console.log(`  ${f}`);
  process.exit(1);
}
console.log(`RESULT: PASS  (${checked} values checked; all within ${FLOAT_TOL.toExponential(0)} absolute)`);