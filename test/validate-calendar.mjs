/**
 * Cross-validation harness for PeakCalendar + NoteSnap.
 *
 * Compares the TypeScript port against reference vectors produced by the
 * ORIGINAL Swift implementation (reference/swift-core + reference/vec-calendar).
 *
 * Run:  TZ=UTC node test/validate-calendar.mjs
 *       TZ=UTC node test/validate-calendar.mjs reference/vectors-calendar.json
 *
 * With no arguments it validates BOTH vector sets (UTC and America/New_York).
 *
 * ---------------------------------------------------------------------------
 * TOLERANCES - all three are derived, not fitted
 * ---------------------------------------------------------------------------
 *
 * 1. TOL = 1e-9 for every continuous field. Both implementations perform the
 *    same double operations on the same inputs, so agreement is exact: the
 *    measured maximum is 0 for months.openingDegree, months.lengthDays and
 *    snap.node.degree, 1.1e-16 - a single double ULP of a cosine - for
 *    nodeOpacity.o, and 2.1e-13 for position.fractionThroughMonth (that last
 *    one is the year-fraction gap of 3.7e-15 in note 3, normalised by the
 *    narrowest month span, 1/7 - 1/8 = 1/56 = 0.017857, which amplifies it
 *    exactly 56x; 1e-9 still leaves ~4800x margin).
 *
 * 2. BOUNDARY_TOL = 1e-3 + 1e-6 for `nextDayBoundary`'s returned Date. Swift
 *    returns a `Date` holding raw Double seconds; the port must return a JS
 *    `Date`, which TimeClips to an integer number of milliseconds. The port's
 *    result is therefore truncated onto the millisecond grid, a discrepancy of
 *    strictly less than 1 ms, plus <=2.4e-7 s from Swift's own seconds-since-
 *    2001 Double rounding at 2015-era magnitudes. Both are representation
 *    limits of the two Date types, not algorithm differences - the same
 *    limitation src/core/fadeMath.ts already documents for cycleBoundary.
 *
 * 3. FRAC_RESOLUTION = 1e-14 of a year fraction, used ONLY to decide whether a
 *    sub-second instant's *discrete* answer (monthIndex / dayOfMonth, and the
 *    next-day boundary derived from them) is resolvable at all. It is not a
 *    value tolerance. Swift's `Date` is a Double of seconds since 2001-01-01
 *    and `Date(timeIntervalSince1970:)` rounds at a ~4.5e8 magnitude (ULP
 *    ~6e-8 s), while the port's input is an exact integer millisecond count;
 *    `timeIntervalSince` therefore differs from the port's millisecond
 *    difference by up to ~1.2e-7 s. Measured maximum over these vectors:
 *    |yearFraction(TS) - yearFraction(Swift)| = 3.69e-15. An instant sitting
 *    inside that window of a month opening or a day rollover has no
 *    well-defined month/day - which one it is depends on how the `Date` was
 *    built, not on the algorithm. Every whole-second instant is exempt from
 *    this gate and must match EXACTLY, because for those both sides do exact
 *    integer-second arithmetic and agree bit-for-bit.
 * ---------------------------------------------------------------------------
 */

import { readFileSync } from "node:fs";
import { buildShapeList, defaultShapes } from "../dist/core/geometry.js";
import { months, position, nextDayBoundary } from "../dist/core/peakCalendar.js";
import { snap, nodeOpacity } from "../dist/core/noteSnap.js";
import { degree } from "../dist/core/timeFrame.js";
import { tropicalYearDays } from "../dist/core/timeFrame.js";

const TOL = 1e-9;
const BOUNDARY_TOL = 1e-3 + 1e-6;
const FRAC_RESOLUTION = 1e-14;

// --- thresholds --------------------------------------------------------------

/** Every month opening (plus the wrap at 1.0) and every intra-month day rollover. */
const THRESHOLDS = [];
for (const m of months) {
  const start = m.openingDegree / 360;
  THRESHOLDS.push(start);
  for (let k = 1; k <= m.dayCount; k++) THRESHOLDS.push(start + k / tropicalYearDays);
}
THRESHOLDS.push(1.0);

function distanceToThreshold(frac) {
  let best = Number.POSITIVE_INFINITY;
  for (const th of THRESHOLDS) {
    const d = Math.abs(frac - th);
    if (d < best) best = d;
  }
  return best;
}

/** The port's own year fraction, mirroring PeakCalendar.yearFraction. */
function portYearFraction(at) {
  let frac = degree("year", at) / 360;
  frac = frac % 1;
  if (frac < 0) frac += 1;
  return frac;
}

// --- vector input reconstruction (must mirror VecCalendar/main.swift) ---------

function uuid(n) {
  return `00000000-0000-0000-0000-${String(n).padStart(12, "0")}`;
}

const degA = { year: 0.0, moon: 30.0, quarterMoon: 60.0, day: 90.0, hour: 53.0, minute: 359.0 };
const degB = { year: 120.0, moon: 121.0, day: 44.9, hour: 45.0 };
const degC = { year: 359.9, moon: 180.0, quarterMoon: 179.999, day: 0.0, hour: 0.0, minute: 0.0 };
const degD = { year: 7.0 };
const degE = { year: 200.0, moon: 200.5, quarterMoon: 201.0, day: 202.0, hour: 203.0, minute: 204.0 };
const degF = {
  year: 51.42857142857143, moon: 51.42857142857143, quarterMoon: 51.42857142857143,
  day: 51.42857142857143, hour: 51.42857142857143, minute: 51.42857142857143,
};

const noteTemplates = {
  empty: [],
  singleRecent: [[1, -3600.0, degA]],
  threeRecent: [[1, -3600.0, degA], [2, -7200.0, degB], [3, -10800.0, degC]],
  stale: [[1, -10 * 86400.0, degD], [2, -100 * 86400.0, degE]],
  futureAndNow: [[1, 86400.0, degC], [2, -1.0, degB], [3, 0.0, degE]],
  colliding: [[1, -1.0, degF], [2, -2.0, degF], [3, -3.0, degF]],
};

const shapeSets = {
  default: () => defaultShapes,
  regulars: () => buildShapeList(3, 8, false),
  narrow: () => buildShapeList(4, 6, true),
  empty: () => [],
};

function notesFor(label, nowMs) {
  return (noteTemplates[label] ?? []).map(([n, off, degs]) => ({
    id: uuid(n),
    timestamp: new Date(nowMs + off * 1000),
    degrees: degs,
  }));
}

// --- harness -----------------------------------------------------------------

const maxima = new Map();
let failures = 0;
const problems = [];
const stringProblems = [];

function track(name, got, want, tol) {
  const d = Math.abs(got - want);
  const cur = maxima.get(name) ?? 0;
  maxima.set(name, d > cur ? d : cur);
  if (!(d <= tol)) {
    failures++;
    if (problems.length < 15) {
      problems.push(`${name}: got ${got} want ${want} (diff ${d.toExponential(3)} > ${tol})`);
    }
  }
}

function eq(name, got, want) {
  if (got !== want) {
    failures++;
    if (stringProblems.length < 15) {
      stringProblems.push(`${name}: got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
    }
  }
}

function runOne(vectorPath) {
  const vectors = JSON.parse(readFileSync(vectorPath, "utf8"));
  const before = failures;

  let exactDiscrete = 0;
  let gatedDiscrete = 0;
  let gatedBoundaries = 0;
  let worstGap = 0;
  let worstBoundaryGap = 0;

  // --- 1. the month table ---------------------------------------------------
  eq("months.length", months.length, vectors.months.length);
  for (let i = 0; i < Math.min(months.length, vectors.months.length); i++) {
    const g = months[i];
    const w = vectors.months[i];
    eq(`months[${i}].number`, g.number, w.number);
    eq(`months[${i}].name`, g.name, w.name);
    eq(`months[${i}].shorthand`, g.shorthand, w.shorthand);
    eq(`months[${i}].numerator`, g.numerator, w.numerator);
    eq(`months[${i}].harmonic`, g.harmonic, w.harmonic);
    eq(`months[${i}].coincidingHarmonics`, JSON.stringify(g.coincidingHarmonics),
      JSON.stringify(w.coincidingHarmonics));
    eq(`months[${i}].id`, g.id, w.id);
    eq(`months[${i}].dayCount`, g.dayCount, w.dayCount);
    eq(`months[${i}].fractionLabel`, g.fractionLabel, w.fractionLabel);
    track("months.openingDegree", g.openingDegree, w.openingDegree, TOL);
    track("months.lengthDays", g.lengthDays, w.lengthDays, TOL);
  }

  // --- 2. position(at:) -----------------------------------------------------
  for (const w of vectors.positions) {
    const at = new Date(w.ms);
    const g = position(at);

    // Positive assertion of the representation gap (see FRAC_RESOLUTION).
    const gap = Math.abs(portYearFraction(at) - w.yf);
    if (gap > worstGap) worstGap = gap;

    const resolvable = w.aligned || distanceToThreshold(w.yf) > FRAC_RESOLUTION;
    if (resolvable) {
      // fractionThroughMonth is normalised by the month's own span, so it is
      // only comparable when both sides agree on which month it is.
      track("position.fractionThroughMonth", g.fractionThroughMonth, w.frac, TOL);
      eq(`position(${w.ms}).monthIndex`, g.monthIndex, w.mi);
      eq(`position(${w.ms}).dayOfMonth`, g.dayOfMonth, w.dom);
      exactDiscrete++;
    } else {
      // Unresolvable: the instant is inside FRAC_RESOLUTION of a month opening
      // or a day rollover, so neither answer is more correct. Still require the
      // two to differ by at most one month, and require the gap to be within
      // the declared resolution.
      gatedDiscrete++;
      if (Math.abs(g.monthIndex - w.mi) > 1) {
        failures++;
        problems.push(`position(${w.ms}): unresolvable but monthIndex differs by >1 (got ${g.monthIndex} want ${w.mi})`);
      }
      if (gap > FRAC_RESOLUTION) {
        failures++;
        problems.push(`position(${w.ms}): gated row's year fraction gap ${gap.toExponential(3)} exceeds FRAC_RESOLUTION`);
      }
    }
  }

  // --- 3. nextDayBoundary(after:) -------------------------------------------
  for (const w of vectors.boundaries) {
    const at = new Date(w.beforeMs);
    const got = nextDayBoundary(at).getTime() / 1000;
    const gap = Math.abs(portYearFraction(at) - w.yf);
    if (gap > worstBoundaryGap) worstBoundaryGap = gap;

    const resolvable = w.aligned || distanceToThreshold(w.yf) > FRAC_RESOLUTION;
    if (resolvable) {
      eq(`boundary(${w.beforeMs}).monthIndex`, position(at).monthIndex, w.mi);
      eq(`boundary(${w.beforeMs}).dayOfMonth`, position(at).dayOfMonth, w.dom);
      track("nextDayBoundary.after", got, w.after, BOUNDARY_TOL);
    } else {
      // The day the boundary lands on is unresolvable, so the two answers may
      // legitimately be one day/partial-day apart. Assert that bound, plus the
      // same year-fraction resolution limit.
      gatedBoundaries++;
      track("nextDayBoundary.after(unresolved)", got, w.after, 86400 + BOUNDARY_TOL);
      if (gap > FRAC_RESOLUTION) {
        failures++;
        problems.push(`nextDayBoundary(${w.beforeMs}): gated row's year fraction gap ${gap.toExponential(3)} exceeds FRAC_RESOLUTION`);
      }
    }
  }

  // --- 4. NoteSnap.snap -----------------------------------------------------
  for (const w of vectors.snaps) {
    const shapes = shapeSets[w.shapesKey]();
    const notes = notesFor(w.label, w.nowMs);
    const got = snap(notes, w.circle, shapes, w.lookbackCycles, new Date(w.nowMs));
    const tag = `${w.circle}/${w.label}/lb${w.lookbackCycles}/${w.shapesKey}@${w.nowMs}`;

    // Swift's Dictionary order is not stable, so compare as sets keyed by id.
    const gm = new Map(got.map((n) => [n.id, n]));
    const wm = new Map(w.nodes.map((n) => [n.id, n]));
    if (gm.size !== wm.size) {
      failures++;
      if (problems.length < 15) {
        problems.push(`snap ${tag}: node count got ${gm.size} want ${wm.size} (ids got [${[...gm.keys()]}] want [${[...wm.keys()]}]`);
      }
    }
    for (const [id, wn] of wm) {
      const gn = gm.get(id);
      if (!gn) {
        failures++;
        if (problems.length < 15) problems.push(`snap ${tag}: missing node id ${id}`);
        continue;
      }
      track("snap.node.degree", gn.degree, wn.degree, TOL);
      eq(`snap ${tag} id${id}.noteIDs`, JSON.stringify([...gn.noteIDs].sort()),
        JSON.stringify([...wn.noteIDs].sort()));
    }
  }

  // --- 5. NoteSnap.nodeOpacity ---------------------------------------------
  for (const w of vectors.nodeOps) {
    const got = nodeOpacity(w.nodeDegree, w.currentDegree, shapeSets[w.shapesKey](), w.fadeFraction);
    track("nodeOpacity.o", got, w.o, TOL);
  }

  // --- report ---------------------------------------------------------------
  const tz = vectors.meta.timezone;
  console.log(`vectors   : ${vectorPath}`);
  console.log(`swift TZ  : ${tz}   node TZ: ${process.env.TZ ?? "(system)"}`);
  console.log(`months    : ${vectors.months.length} rows`);
  console.log(`positions : ${vectors.positions.length} rows (${exactDiscrete} discrete results asserted exactly, ${gatedDiscrete} gated as unresolvable)`);
  console.log(`boundaries: ${vectors.boundaries.length} rows (${gatedBoundaries} gated as unresolvable)`);
  console.log(`snaps     : ${vectors.snaps.length} cases`);
  console.log(`nodeOps   : ${vectors.nodeOps.length} rows`);
  console.log(`year-fraction gap TS vs Swift: max ${worstGap.toExponential(3)} (positions), ${worstBoundaryGap.toExponential(3)} (boundaries); declared resolution ${FRAC_RESOLUTION.toExponential(3)}`);
  console.log("");
  console.log("max absolute deviation per field (Swift vs TypeScript):");
  for (const [k, v] of [...maxima.entries()].sort((a, b) => b[1] - a[1])) {
    console.log(`  ${k.padEnd(34)} ${v.toExponential(3)}`);
  }
  console.log("");

  return { failed: failures - before, gatedDiscrete: gatedDiscrete + gatedBoundaries };
}

const paths = process.argv.length > 2
  ? process.argv.slice(2)
  : ["reference/vectors-calendar.json", "reference/vectors-calendar-ny.json"];

const results = [];
for (const p of paths) results.push({ path: p, ...runOne(p) });

if (stringProblems.length) {
  console.log(`text/int mismatches (${stringProblems.length} shown, max 15):`);
  for (const s of stringProblems) console.log(`  ${s}`);
  console.log("");
}
if (problems.length) {
  console.log(`numeric mismatches (${problems.length} shown, max 15):`);
  for (const p of problems) console.log(`  ${p}`);
  console.log("");
}

const totalFail = results.reduce((a, r) => a + r.failed, 0);
const totalGated = results.reduce((a, r) => a + r.gatedDiscrete, 0);
if (totalFail) {
  console.log(`RESULT: FAIL  (${totalFail} mismatches across ${results.length} vector set(s))`);
  process.exit(1);
}
console.log(`RESULT: PASS  ${results.map((r) => r.path).join(" + ")} - every aligned value exact, ${totalGated} sub-second row(s) gated within FRAC_RESOLUTION`);
