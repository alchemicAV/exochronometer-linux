/**
 * Validates the node-date-label port against vectors emitted by the verbatim
 * Swift originals in reference/vec-nodelabels/.
 *
 * Run:  TZ=America/New_York node test/validate-nodelabels.mjs reference/vectors-nodelabels-ny.json
 */

import { readFileSync } from "node:fs";
import { cycleStartMs, nodeDateMs, nodeLabel, nodeLabelPattern } from "../dist/core/timeLabels.js";

const vectorPath = process.argv[2];
if (!vectorPath) {
  console.error("usage: node test/validate-nodelabels.mjs <vectors.json>");
  process.exit(2);
}
const vectors = JSON.parse(readFileSync(vectorPath, "utf8"));

// The Swift side emits epoch milliseconds rounded to an Int64, so an exact
// comparison would fail by up to half a millisecond purely from that encoding.
// One millisecond is therefore the floor; anything beyond it is a real defect.
const MS_TOL = 1.0;

const maxima = new Map();
const problems = [];
let bad = 0;
let checked = 0;
let labelBad = 0;

function track(name, diff) {
  const cur = maxima.get(name) ?? 0;
  if (diff > cur) maxima.set(name, diff);
}

for (const r of vectors.rows ?? []) {
  checked++;

  const startGot = cycleStartMs(r.tf, new Date(r.ms));
  const startDiff = Math.abs(startGot - r.cycleStartMs);
  track("cycleStartMs", startDiff);
  if (startDiff > MS_TOL) {
    bad++;
    if (problems.length < 10) {
      problems.push(`cycleStart ${r.tf} @${r.ms}: got ${startGot} want ${r.cycleStartMs} (diff ${startDiff})`);
    }
  }

  const nodeGot = nodeDateMs(r.deg, r.tf, new Date(r.ms));
  const nodeDiff = Math.abs(nodeGot - r.nodeMs);
  track("nodeDateMs", nodeDiff);
  if (nodeDiff > MS_TOL) {
    bad++;
    if (problems.length < 10) {
      problems.push(`nodeDate ${r.tf} deg${r.deg} @${r.ms}: got ${nodeGot} want ${r.nodeMs} (diff ${nodeDiff})`);
    }
  }

  const labelGot = nodeLabel(r.tf, new Date(nodeGot));
  if (labelGot !== r.label) {
    labelBad++;
    if (problems.length < 10) {
      problems.push(`label ${r.tf} deg${r.deg} @${r.ms}: got "${labelGot}" want "${r.label}"`);
    }
  }

  const patGot = nodeLabelPattern(r.tf);
  const patWant = (vectors.formats ?? []).find((f) => f.tf === r.tf);
  if (patWant && patGot !== patWant.format) {
    bad++;
    if (problems.length < 10) {
      problems.push(`format ${r.tf}: got "${patGot}" want "${patWant.format}"`);
    }
  }
}

console.log(`vectors : ${vectorPath}`);
console.log(`swift TZ: ${vectors.timezone}   node TZ: ${process.env.TZ ?? "(system)"}`);
console.log(`rows    : ${checked}`);
console.log("");
console.log("max absolute deviation:");
for (const [k, v] of [...maxima.entries()].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${k.padEnd(16)} ${v.toExponential(3)}`);
}
console.log("");

if (bad || labelBad) {
  console.log(`RESULT: FAIL  (${bad} numeric, ${labelBad} label mismatches)`);
  for (const p of problems) console.log(`  ${p}`);
  process.exit(1);
}
console.log(`RESULT: PASS  (${checked} rows, all labels exact)`);
