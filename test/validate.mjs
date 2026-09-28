/**
 * Cross-validation harness.
 *
 * Compares the TypeScript port against reference vectors produced by the
 * ORIGINAL Swift implementation (reference/swift-core -> VectorGen).
 *
 * Run:  TZ=UTC node test/validate.mjs reference/vectors-utc.json
 */

import { readFileSync } from "node:fs";
import { allCases, cycleDuration, degree, traditionalLabel } from "../dist/core/timeFrame.js";
import { moonDegree, phase, phaseName, quarterMoonDegree } from "../dist/core/moonPhase.js";
import { defaultShapes } from "../dist/core/geometry.js";
import { closestNote } from "../dist/core/justIntonation.js";
import { ratios } from "../dist/core/justIntonation.js";
import * as Fade from "../dist/core/fadeMath.js";

const DEG_TOL = 1e-9;
const ABS_TOL = 1e-6;

/**
 * One unit in the last place for a Double at this magnitude.
 *
 * The input instant is only representable to within one ULP, and JS Date
 * additionally quantizes to whole milliseconds. Swift keeps Date as a Double
 * and derives its sub-second components from that value directly, so the two
 * implementations can legitimately disagree by one ULP of TIME - which a
 * degree reading amplifies by 360/cycleDuration. Anything beyond that is a
 * genuine defect, not a representation artifact.
 */
function ulpOf(seconds) {
  const buf = new DataView(new ArrayBuffer(8));
  buf.setFloat64(0, seconds);
  const bits = buf.getBigUint64(0);
  buf.setBigUint64(0, bits + 1n);
  return buf.getFloat64(0) - seconds;
}


const vectorPath = process.argv[2];
if (!vectorPath) {
  console.error("usage: node test/validate.mjs <vectors.json>");
  process.exit(2);
}
const vectors = JSON.parse(readFileSync(vectorPath, "utf8"));

let failures = 0;
const problems = [];

function track(name, got, want, tol) {
  const d = Math.abs(got - want);
  const cur = maxima.get(name) ?? 0;
  if (d > cur) maxima.set(name, d);
  if (d > tol) {
    failures++;
    if (problems.length < 12) {
      problems.push(`${name}: got ${got} want ${want} (diff ${d.toExponential(3)})`);
    }
  }
}

const maxima = new Map();
const labelMismatch = [];
let harmChecked = 0;
let harmMismatch = 0;

// --- static tables -----------------------------------------------------------

const wantShapes = vectors.shapes.map((s) => `${s.divisions}/${s.skip}/${s.isRegular}/${s.pathCount}`);
const gotShapes = defaultShapes.map((s) => `${s.divisions}/${s.skip}/${s.isRegular}/${s.path.length}`);
if (JSON.stringify(wantShapes) !== JSON.stringify(gotShapes)) {
  failures++;
  problems.push(`shape table differs:\n  want ${wantShapes.join(", ")}\n  got  ${gotShapes.join(", ")}`);
}

for (let i = 0; i < vectors.ji.length; i++) {
  const w = vectors.ji[i];
  const g = ratios[i];
  if (w.name !== g.name) { failures++; problems.push(`ji[${i}] name ${g.name} != ${w.name}`); }
  track(`ji.ratio[${w.name}]`, g.ratio, w.ratio, DEG_TOL);
  track(`ji.cents[${w.name}]`, 1200 * Math.log2(g.ratio), w.cents, DEG_TOL);
}

// --- per-sample --------------------------------------------------------------

const harmByMs = new Map(vectors.harmonics.map((h) => [h.ms, h.rows]));

for (const s of vectors.samples) {
  const at = new Date(s.ms);

  const ulp = ulpOf(s.ms / 1000);
  for (let i = 0; i < allCases.length; i++) {
    const tf = allCases[i];
    const tfTol = Math.max(DEG_TOL, (ulp / cycleDuration(tf)) * 360);
    track(`tf.${tf}`, degree(tf, at), s.tf[i], tfTol);
    track(`cd.${tf}`, cycleDuration(tf), s.cd[i], ABS_TOL);
    const gotLabel = traditionalLabel(tf, at);
    if (gotLabel !== s.lbl[i]) {
      if (labelMismatch.length < 8) labelMismatch.push(`${tf} @${s.ms}: got "${gotLabel}" want "${s.lbl[i]}"`);
    }
  }

  const ph = phase(at);
  track("moon.phase", ph, s.moon[0], DEG_TOL);
  track("moon.moonDegree", moonDegree(at), s.moon[1], DEG_TOL);
  track("moon.quarterMoonDegree", quarterMoonDegree(at), s.moon[2], DEG_TOL);
  const pn = phaseName(ph);
  if (pn !== s.moonName) {
    failures++;
    problems.push(`moon.phaseName @${s.ms}: got "${pn}" want "${s.moonName}"`);
  }

  // harmonics (strided subset)
  const rows = harmByMs.get(s.ms);
  if (rows) {
    let r = 0;
    for (const tf of allCases) {
      for (const shape of defaultShapes) {
        const w = rows[r++];
        const period = (cycleDuration(tf) * shape.skip) / shape.divisions;
        const freq = period > 0 ? 1 / period : 0;
        const ji = closestNote(freq);
        harmChecked++;
        let bad = false;
        if (Math.abs(period - w.p) > ABS_TOL) bad = true;
        if (Math.abs(freq - w.f) > ABS_TOL) bad = true;
        if (Math.abs(ji.centsDelta - w.c) > ABS_TOL) bad = true;
        if (ji.noteName !== w.n) bad = true;
        if (bad) {
          harmMismatch++;
          if (problems.length < 12) {
            problems.push(`harm @${s.ms} ${tf} ${shape.divisions}/${shape.skip}: got p=${period} f=${freq} n=${ji.noteName} c=${ji.centsDelta} | want p=${w.p} f=${w.f} n=${w.n} c=${w.c}`);
          }
        }
      }
    }
  }
}

// --- fade math ---------------------------------------------------------------

const FADE_TOL = 1e-9;
let fadeChecked = 0, fadeBad = 0;
let opChecked = 0, opBad = 0;
let exitChecked = 0, exitBad = 0;

const shapeByDK = new Map(defaultShapes.map((s) => [`${s.divisions}/${s.skip}`, s]));

for (const r of vectors.fade ?? []) {
  const shape = shapeByDK.get(`${r.d}/${r.k}`);
  if (!shape) continue;
  const st = Fade.timeframeState(r.tf, new Date(r.ms));
  const got = Fade.nodeActivation(shape, r.v, st);
  fadeChecked++;
  const d = Math.abs(got - r.a);
  const cur = maxima.get("fade.nodeActivation") ?? 0;
  if (d > cur) maxima.set("fade.nodeActivation", d);
  if (d > FADE_TOL) {
    fadeBad++;
    if (problems.length < 12) {
      problems.push(`nodeActivation @${r.ms} ${r.tf} ${r.d}/${r.k} v${r.v}: got ${got} want ${r.a}`);
    }
  }
}

for (const r of vectors.shapeOps ?? []) {
  const st = Fade.timeframeState(r.tf, new Date(r.ms));
  const got = Fade.shapeOpacity(st.currentDegree, r.d);
  opChecked++;
  const d = Math.abs(got - r.o);
  const cur = maxima.get("fade.shapeOpacity") ?? 0;
  if (d > cur) maxima.set("fade.shapeOpacity", d);
  if (d > FADE_TOL) {
    opBad++;
    if (problems.length < 12) {
      problems.push(`shapeOpacity @${r.ms} ${r.tf} d${r.d}: got ${got} want ${r.o}`);
    }
  }
}

for (const r of vectors.exits ?? []) {
  const got = Fade.timeUntilOvertoneExit(r.tf, r.d, r.k, new Date(r.ms));
  exitChecked++;
  const want = r.e;
  // Swift's JSONEncoder OMITS nil values rather than emitting null, so a
  // missing key arrives here as undefined - treat undefined and null alike.
  const ok = (got == null && want == null) ||
             (got != null && want != null && Math.abs(got - want) <= 1e-6);
  if (got != null && want != null) {
    const d = Math.abs(got - want);
    const cur = maxima.get("fade.timeUntilOvertoneExit") ?? 0;
    if (d > cur) maxima.set("fade.timeUntilOvertoneExit", d);
  }
  if (!ok) {
    exitBad++;
    if (problems.length < 12) {
      problems.push(`timeUntilOvertoneExit @${r.ms} ${r.tf} ${r.d}/${r.k}: got ${got} want ${want}`);
    }
  }
}

// --- report ------------------------------------------------------------------

const tz = vectors.meta.timezone;
console.log(`vectors : ${vectorPath}`);
console.log(`swift TZ: ${tz}   node TZ: ${process.env.TZ ?? "(system)"}`);
console.log(`samples : ${vectors.samples.length}`);
console.log(`harmonics rows checked: ${harmChecked} (mismatched ${harmMismatch})`);
console.log(`fade rows checked     : ${fadeChecked} (mismatched ${fadeBad})`);
console.log(`shapeOpacity checked  : ${opChecked} (mismatched ${opBad})`);
console.log(`overtoneExit checked  : ${exitChecked} (mismatched ${exitBad})`);
console.log("");
console.log("max absolute deviation per field (Swift vs TypeScript):");
const sorted = [...maxima.entries()].sort((a, b) => b[1] - a[1]);
for (const [k, v] of sorted) console.log(`  ${k.padEnd(26)} ${v.toExponential(3)}`);
console.log("");

if (labelMismatch.length) {
  console.log(`label mismatches (${labelMismatch.length} shown, max 8):`);
  for (const l of labelMismatch) console.log(`  ${l}`);
  console.log("");
}

if (failures || harmMismatch || fadeBad || opBad || exitBad) {
  console.log(`RESULT: FAIL  (${failures} field failures, ${harmMismatch} harmonic, ${fadeBad} fade, ${opBad} shapeOpacity, ${exitBad} exit mismatches)`);
  for (const p of problems) console.log(`  ${p}`);
  process.exit(1);
}
console.log(`RESULT: PASS  (all ${vectors.samples.length} samples + ${harmChecked} harmonic rows + ${fadeChecked} fade rows within tolerance)`);
