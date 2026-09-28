/**
 * Validates FrequencyMath + intervalName + shapeName against vectors emitted by
 * reference/vec-freq/ from the verbatim Swift originals.
 *
 * The format helpers use printf rounding; JS toFixed is NOT guaranteed to round
 * identically on binary-boundary values, so this compares the rendered strings
 * exactly over a wide sweep rather than assuming equivalence.
 */

import { readFileSync } from "node:fs";
import {
  audibleMinHz,
  audibleMaxHz,
  hz,
  scaled,
  format,
  formatDuration,
  printfFixed,
} from "../dist/core/frequencyMath.js";
import { intervalName, shapeName } from "../dist/core/intervalNames.js";

const vectors = JSON.parse(readFileSync(process.argv[2], "utf8"));

let checked = 0;
let bad = 0;
const problems = [];
const maxima = new Map();
const formatDiffs = [];

function track(name, diff) {
  const cur = maxima.get(name) ?? 0;
  if (diff > cur) maxima.set(name, diff);
}

// constants
checked += 2;
if (audibleMinHz !== vectors.constants[0]) { bad++; problems.push(`audibleMinHz ${audibleMinHz} != ${vectors.constants[0]}`); }
if (audibleMaxHz !== vectors.constants[1]) { bad++; problems.push(`audibleMaxHz ${audibleMaxHz} != ${vectors.constants[1]}`); }

let durBad = 0;
for (const r of vectors.durations) {
  checked++;
  const got = formatDuration(r.seconds);
  if (got !== r.text) {
    durBad++; bad++;
    if (formatDiffs.length < 12) formatDiffs.push(`formatDuration(${r.seconds}) got "${got}" want "${r.text}"`);
  }
}

let fmtBad = 0;
for (const r of vectors.formats) {
  checked++;
  const got = format(r.hz);
  if (got !== r.text) {
    fmtBad++; bad++;
    if (formatDiffs.length < 12) formatDiffs.push(`format(${r.hz}) got "${got}" want "${r.text}"`);
  }
}

for (const r of vectors.hz) {
  checked++;
  const got = hz(r.period);
  const d = Math.abs(got - r.hz);
  track("hz", d);
  if (d > 1e-12) bad++;
}

for (const r of vectors.scaled) {
  checked++;
  const got = scaled(r.hz, r.octaves);
  const d = Math.abs(got - r.out) / Math.max(1, Math.abs(r.out));
  track("scaled(rel)", d);
  if (d > 1e-12) bad++;
}

let intBad = 0;
for (const r of vectors.intervals) {
  checked++;
  const got = intervalName(r.n, r.k);
  if (got !== r.name) {
    intBad++; bad++;
    if (problems.length < 12) problems.push(`intervalName(${r.n},${r.k}) got "${got}" want "${r.name}"`);
  }
}

let shapeBad = 0;
for (const r of vectors.shapeNames ?? []) {
  checked++;
  const got = shapeName(r.divisions, r.skip);
  if (got !== r.name) {
    shapeBad++; bad++;
    if (problems.length < 12) problems.push(`shapeName(${r.divisions},${r.skip}) got "${got}" want "${r.name}"`);
  }
}

// printfFixed at 2 and 3 digits (string equality)
let printfBad = 0;
const printfByDigits = new Map();
for (const r of vectors.printf ?? []) {
  checked++;
  const got = printfFixed(r.value, r.digits);
  const c = printfByDigits.get(r.digits) ?? { n: 0, bad: 0 };
  c.n++;
  if (got !== r.text) {
    c.bad++; printfBad++; bad++;
    if (formatDiffs.length < 12) formatDiffs.push(`printfFixed(${r.value}, ${r.digits}) got "${got}" want "${r.text}"`);
  }
  printfByDigits.set(r.digits, c);
}

console.log(`durations : ${vectors.durations.length}  string mismatches ${durBad}`);
console.log(`formats   : ${vectors.formats.length}  string mismatches ${fmtBad}`);
console.log(`hz rows   : ${vectors.hz.length}`);
console.log(`scaled    : ${vectors.scaled.length}`);
console.log(`intervals : ${vectors.intervals.length}  string mismatches ${intBad}`);
console.log(`shapeNames: ${(vectors.shapeNames ?? []).length}  string mismatches ${shapeBad}`);
for (const [d, c] of [...printfByDigits.entries()].sort((a, b) => a[0] - b[0])) {
  console.log(`printf %.${d}f : ${c.n}  string mismatches ${c.bad}`);
}
console.log("");
console.log("max absolute / relative deviation:");
for (const [k, v] of [...maxima.entries()].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${k.padEnd(14)} ${v.toExponential(3)}`);
}
console.log("");

if (formatDiffs.length) {
  console.log("format string differences:");
  for (const d of formatDiffs) console.log(`  ${d}`);
  console.log("");
}

if (bad) {
  console.log(`RESULT: FAIL  (${bad} of ${checked} values differ)`);
  for (const p of problems) console.log(`  ${p}`);
  process.exit(1);
}
console.log(`RESULT: PASS  (${checked} values; all format strings byte-identical)`);