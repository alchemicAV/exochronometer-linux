// How many tones does each timeframe contribute, and how often is the moon
// group too small for any Lissajous pair?
//
// LissajousView builds pairs within a timeframe and needs >= 2 tones. The moon
// section showed an empty placeholder box, which the original also draws
// (LissajousSection: `if pairs.isEmpty { RoundedRectangle... }`). This quantifies
// how often that happens and for which timeframes.
import { activeTonesForScales, isFundamental } from "../dist/core/harmonicAnalysis.js";

const SCALING = 23;
const ORDER = ["hour", "day", "quarterMoon", "moon", "year"];
const SAMPLES = 288;   // every 5 minutes over a day

const counts = {};
for (const tf of ORDER) counts[tf] = { min: 1e9, max: 0, empty: 0, n: 0 };
const empties = {};

for (let k = 0; k < SAMPLES; k++) {
  const date = new Date(Date.now() + k * 300 * 1000);
  const tones = activeTonesForScales(date, [SCALING]);
  const grouped = {};
  for (const t of tones) (grouped[t.timeframe] ||= []).push(t);
  for (const tf of ORDER) {
    const g = grouped[tf] || [];
    const c = counts[tf];
    c.min = Math.min(c.min, g.length);
    c.max = Math.max(c.max, g.length);
    c.n++;
    if (g.length < 2) {
      c.empty++;
      empties[tf] = (empties[tf] || 0) + 1;
    }
  }
}

console.log(`sampled ${SAMPLES} instants across a day (every 5 min), scaling ${SCALING}\n`);
console.log("timeframe      tones min/max   instants with <2 tones (blank placeholder)");
for (const tf of ORDER) {
  const c = counts[tf];
  const pct = (100 * c.empty / c.n).toFixed(0);
  console.log(`${tf.padEnd(14)} ${String(c.min).padStart(4)}/${String(c.max).padEnd(4)}` +
              `        ${String(c.empty).padStart(4)}/${c.n}  (${pct}%)`);
}

// What does the moon group look like at a representative instant?
const now = new Date();
const g = activeTonesForScales(now, [SCALING]).filter((t) => t.timeframe === "moon");
console.log(`\nmoon tones right now (${g.length}):`);
for (const t of g) {
  console.log(`  divisions=${t.divisions} skip=${t.skip} freq=${t.frequency.toExponential(3)}` +
              ` amp=${t.amplitude.toFixed(4)} fundamental=${isFundamental(t)}`);
}
