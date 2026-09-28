// What is the phase portrait actually plotting?
//
// Segments in the 30 ms window jump up to 680 px, which is far too long for a
// smooth curve -- that only happens if the tones are far above the sampling
// rate. Print the tone set so the aliasing question is answered with numbers
// rather than guessed at.
import { activeTonesForScales, isFundamental } from "../dist/core/harmonicAnalysis.js";

const SCALING = 23;
const WINDOW = 0.030;
const SAMPLES = 800;

const date = new Date();
const all = activeTonesForScales(date, [SCALING]);
const tones = all.filter((t) => !isFundamental(t));

console.log(`scaling ${SCALING}: ${all.length} tones, ${tones.length} after fundamentals-off\n`);
console.log("timeframe      div skip   frequency Hz      cycles in 30ms");
const rows = tones.slice().sort((a, b) => a.frequency - b.frequency);
for (const t of rows) {
  const cycles = t.frequency * WINDOW;
  console.log(
    `${String(t.timeframe).padEnd(13)} ${String(t.divisions).padStart(3)} ${String(t.skip).padStart(4)}` +
    `   ${t.frequency.toExponential(3).padStart(12)}   ${cycles.toFixed(1).padStart(12)}`
  );
}

const nyquist = SAMPLES / 2 / WINDOW;
console.log(`\nNyquist for ${SAMPLES} samples over ${WINDOW * 1000} ms: ${nyquist.toFixed(0)} Hz`);
const aliased = tones.filter((t) => t.frequency > nyquist).length;
console.log(`${aliased} of ${tones.length} tones are ABOVE Nyquist -> they alias`);
const maxCycles = Math.max(...tones.map((t) => t.frequency * WINDOW));
console.log(`most cycles traced by any single tone in the window: ${maxCycles.toFixed(0)}`);
