/**
 * Validates HarmonicColor against vectors emitted by reference/vec-color/ from
 * verbatim copies of the Swift originals.
 */

import { readFileSync } from "node:fs";
import { hue, hueToRGB, blendedColor } from "../dist/core/harmonicColor.js";

const vectors = JSON.parse(readFileSync(process.argv[2], "utf8"));

let checked = 0;
let bad = 0;
const problems = [];
let maxDev = 0;

function near(got, want, what) {
  const d = Math.abs(got - want);
  if (d > maxDev) maxDev = d;
  if (!(d <= 1e-12)) {
    bad++;
    if (problems.length < 12) problems.push(`${what} got ${got} want ${want}`);
  }
}

let hueBad = 0;
for (const r of vectors.hues) {
  checked++;
  const before = bad;
  near(hue(r.freq), r.hue, `hue(${r.freq})`);
  if (bad > before) hueBad++;
}

let rgbBad = 0;
for (const r of vectors.rgbs) {
  checked += 3;
  const before = bad;
  const c = hueToRGB(r.hue);
  near(c.r, r.r, `hueToRGB(${r.hue}).r`);
  near(c.g, r.g, `hueToRGB(${r.hue}).g`);
  near(c.b, r.b, `hueToRGB(${r.hue}).b`);
  if (bad > before) rgbBad++;
}

let blendBad = 0;
for (const r of vectors.blends) {
  checked += 3;
  const before = bad;
  const tones = r.freqs.map((f, i) => ({ frequency: f, amplitude: r.amps[i] }));
  const c = blendedColor(tones);
  near(c.r, r.r, `blend.r`);
  near(c.g, r.g, `blend.g`);
  near(c.b, r.b, `blend.b`);
  if (bad > before) blendBad++;
}

console.log(`hues   : ${vectors.hues.length}  mismatches ${hueBad}`);
console.log(`rgb    : ${vectors.rgbs.length}  mismatches ${rgbBad}`);
console.log(`blends : ${vectors.blends.length}  mismatches ${blendBad}`);
console.log("");
console.log(`max absolute deviation: ${maxDev.toExponential(3)}`);
console.log("");

if (bad) {
  console.log(`RESULT: FAIL  (${bad} of ${checked} values differ)`);
  for (const p of problems) console.log(`  ${p}`);
  process.exit(1);
}
console.log(`RESULT: PASS  (${checked} values checked; all within 1e-12)`);