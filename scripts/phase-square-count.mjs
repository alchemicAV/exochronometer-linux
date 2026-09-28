// How many 2px squares does each phase curve need, per mode?
//
// STANDARD draws one curve from all timeframes over a fixed 30 ms window; the
// hour tones (14-18.6 kHz) are above that window's Nyquist, so the trace is a
// wild mesh with ~680 px segments and needs ~112k squares. NORMALIZED gives
// each timeframe its own window scaled to its cycle, so its curves should be
// far shorter. The caps have to fit both.
import { activeTonesForScales, isFundamental } from "../dist/core/harmonicAnalysis.js";
import { cycleDuration } from "../dist/core/timeFrame.js";

const SCALING = 23;
const DAY_WINDOW = 0.030;
const SAMPLES = 800;
const R = Math.min(1120, 820) / 2 - 8;
const ORDER = ["year", "moon", "quarterMoon", "day", "hour", "minute"];

function tonesAt(date) {
  return activeTonesForScales(date, [SCALING]).filter((t) => !isFundamental(t));
}

function squaresFor(tones, windowSeconds) {
  const sigs = [], deriv = [];
  let peakSig = 0, peakDeriv = 0;
  for (let i = 0; i < SAMPLES; i++) {
    const t = (i / SAMPLES) * windowSeconds;
    let s = 0, d = 0;
    for (const tone of tones) {
      const w = 2 * Math.PI * tone.frequency;
      s += Math.sin(w * t) * tone.amplitude;
      d += Math.cos(w * t) * tone.amplitude * w;
    }
    sigs.push(s); deriv.push(d);
    peakSig = Math.max(peakSig, Math.abs(s));
    peakDeriv = Math.max(peakDeriv, Math.abs(d));
  }
  if (!(peakSig > 0) || !(peakDeriv > 0)) return 0;
  const sScale = R / peakSig, dScale = R / peakDeriv;
  let squares = 1, px = null, py = null;
  for (let i = 0; i < SAMPLES; i++) {
    const x = sigs[i] * sScale, y = -deriv[i] * dScale;
    if (px !== null) {
      const span = Math.max(Math.abs(x - px), Math.abs(y - py));
      squares += Math.max(1, Math.ceil(span / 2));
    }
    px = x; py = y;
  }
  return squares;
}

let stdWorst = 0, normWorst = 0, normTotalWorst = 0;
for (let k = 0; k < 8; k++) {
  const date = new Date(Date.now() + k * 2400 * 1000);
  const tones = tonesAt(date);
  const std = squaresFor(tones, DAY_WINDOW);
  stdWorst = Math.max(stdWorst, std);

  const grouped = {};
  for (const t of tones) (grouped[t.timeframe] ||= []).push(t);
  let total = 0;
  for (const tf of ORDER) {
    const g = grouped[tf];
    if (!g || !g.length) continue;
    const w = DAY_WINDOW * (cycleDuration(tf) / 86400.0);
    const n = squaresFor(g, w);
    normWorst = Math.max(normWorst, n);
    total += n;
  }
  normTotalWorst = Math.max(normTotalWorst, total);
}

console.log(`STANDARD  one curve : worst ${stdWorst} squares`);
console.log(`NORMALIZED worst curve: ${normWorst} squares`);
console.log(`NORMALIZED all curves : worst ${normTotalWorst} squares (the number that matters)`);
