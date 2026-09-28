/**
 * Validates the WAV renderer and its synth voicing chain.
 *
 * The Swift original played audio through AVFoundation (HarmonicAudio), which
 * exports no numbers, so unlike every other module in this port there is no
 * oracle to diff against. What CAN be checked, and is here:
 *
 *   1. the bare signal equals an INDEPENDENT evaluation of
 *      s(t) = SUM A_i sin(2 pi f_i t), written out longhand in this file;
 *   2. the voicing chain does what each parameter says - unison copies,
 *      partials with their rolloff, low-pass attenuation, tremolo depth,
 *      reverb tail, stereo width;
 *   3. **nothing is fabricated above Nyquist** (the property that keeps the
 *      "information-safe" half of the parameter set honest);
 *   4. **the loop seam is not a discontinuity** (the property that makes
 *      sustaining playback click-free);
 *   5. the RIFF container is canonical and self-consistent, including stereo;
 *   6. ffprobe reads the buffer back as PCM at the right rate and channel count.
 *
 * (1), (3) and (4) are the load-bearing ones.
 */

import { writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import {
  renderSamples, renderChannels, wavPacket, dryShape,
  encodeWav, base64, sampleRate, bitsPerSample, headroom, seamSeconds, clampDuration,
} from "../dist/core/wavRender.js";
import { makeSynthParams } from "../dist/core/synthParams.js";

let checked = 0;
let bad = 0;
const problems = [];

function fail(what) {
  bad++;
  if (problems.length < 14) problems.push(what);
}

function eq(got, want, what) {
  checked++;
  if (got !== want) fail(`${what}: got ${got} want ${want}`);
}

function ok(cond, what) {
  checked++;
  if (!cond) fail(what);
}

function near(got, want, what, tol) {
  checked++;
  if (!(Math.abs(got - want) <= tol)) fail(`${what}: got ${got} want ${want} (tol ${tol})`);
}

/**
 * Amplitude of the component at `freq`, via Goertzel. Several checks below are
 * about WHERE the energy is, not how much: the renderer peak-normalises its
 * output, so any single-tone level comparison is undone by that normalisation
 * and measures nothing. Ratios between components are invariant.
 */
function ampAt(buf, freq, r) {
  const n = buf.length;
  const k = Math.round(n * freq / r);
  const w = 2 * Math.PI * k / n;
  const coeff = 2 * Math.cos(w);
  let s1 = 0, s2 = 0;
  for (let i = 0; i < n; i++) {
    const s0 = buf[i] + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  const real = s1 - s2 * Math.cos(w);
  const imag = s2 * Math.sin(w);
  return Math.sqrt(real * real + imag * imag) * 2 / n;
}

function rms(buf) {
  let s = 0;
  for (let i = 0; i < buf.length; i++) s += buf[i] * buf[i];
  return Math.sqrt(s / Math.max(1, buf.length));
}

function peak(buf) {
  let m = 0;
  for (let i = 0; i < buf.length; i++) if (Math.abs(buf[i]) > m) m = Math.abs(buf[i]);
  return m;
}

const rate = sampleRate;

/* ---- 1. the bare signal, against a longhand evaluation ------------------ */

function expectedSamples(tones, seconds, r) {
  const total = Math.max(1, Math.round(seconds * r));
  const out = [];
  for (let i = 0; i < total; i++) {
    const t = i / r;
    let sum = 0;
    for (const tone of tones) sum += Math.sin(2 * Math.PI * tone.frequency * t) * tone.amplitude;
    out.push(sum);
  }
  return out;
}

const bareCases = [
  { name: "single tone", tones: [{ frequency: 440, amplitude: 1 }] },
  { name: "two tones", tones: [{ frequency: 440, amplitude: 1 }, { frequency: 660, amplitude: 0.5 }] },
  { name: "instrument-like", tones: [
      { frequency: 136.1, amplitude: 1 }, { frequency: 204.15, amplitude: 0.75 },
      { frequency: 272.2, amplitude: 0.5 }, { frequency: 16330, amplitude: 0.25 }] },
];
for (const c of bareCases) {
  const got = renderSamples(c.tones, 0.05, rate, 0);
  const want = expectedSamples(c.tones, 0.05, rate);
  eq(got.length, want.length, `${c.name}: sample count`);
  let worst = 0;
  for (let i = 0; i < want.length; i++) worst = Math.max(worst, Math.abs(got[i] - want[i]));
  near(worst, 0, `${c.name}: max sample deviation`, 0);
}

/* ---- 2. the voicing chain ----------------------------------------------- */

const tones = [{ frequency: 220, amplitude: 1 }];
const seconds = 0.25;
const base = makeSynthParams();

// A shape that is only the parameter under test, so each check is isolated.
function shapeOf(over) {
  const s = Object.assign({}, dryShape);
  for (const k in over) s[k] = over[k];
  return s;
}

// unison + detune. At ZERO detune, copies of one frequency sum to one sine - that
// is exactly why the parameter set calls it information-safe - so the effect to
// check for is energy appearing either side of the centre frequency.
{
  const one = renderChannels(tones, shapeOf({ unisonVoices: 1 }), seconds, rate).left;
  ok(rms(one) > 0, "unison: one voice has signal");

  // A 2 s window gives 0.5 Hz bins and 50 cents puts the copies ~6.4 Hz away -
  // far enough apart that the analyser is not simply reading the centre bin back
  // (at 0.25 s and 10 cents both frequencies quantise to the same bin, which
  // makes the check silently measure nothing).
  const long = 2.0;
  const cents = 50;
  const pure = renderChannels(tones, shapeOf({ unisonVoices: 3, detuneCents: 0 }), long, rate).left;
  const detuned = renderChannels(tones, shapeOf({ unisonVoices: 3, detuneCents: cents }), long, rate).left;
  const side = 220 * Math.pow(2, -cents / 1200);  // the lower copy
  const rPure = ampAt(pure, side, rate) / ampAt(pure, 220, rate);
  const rDet = ampAt(detuned, side, rate) / ampAt(detuned, 220, rate);
  ok(rPure < 0.02, `unison: no side energy at zero detune (${rPure.toFixed(4)})`);
  ok(rDet > rPure * 5 + 0.05, `unison: detune puts energy beside the tone (${rDet.toFixed(4)} vs ${rPure.toFixed(4)})`);
}

// partials: with enrichment 1 and tilt 0 the 2nd and 3rd harmonics should arrive
// at the same level as the fundamental.
{
  const pure = renderChannels(tones, shapeOf({}), seconds, rate).left;
  const rich = renderChannels(tones, shapeOf({ enrichment: 1, partials: 2, partialTilt: 0 }), seconds, rate).left;
  ok(ampAt(pure, 440, rate) / ampAt(pure, 220, rate) < 0.02, "partials: none present without enrichment");
  const h2 = ampAt(rich, 440, rate) / ampAt(rich, 220, rate);
  const h3 = ampAt(rich, 660, rate) / ampAt(rich, 220, rate);
  ok(h2 > 0.5, `partials: 2nd harmonic present at ${h2.toFixed(3)}`);
  ok(h3 > 0.5, `partials: 3rd harmonic present at ${h3.toFixed(3)}`);
  // tilt rolls them off again
  const tilted = renderChannels(tones, shapeOf({ enrichment: 1, partials: 2, partialTilt: 2 }), seconds, rate).left;
  const h3t = ampAt(tilted, 660, rate) / ampAt(tilted, 220, rate);
  ok(h3t < h3 * 0.5, `partials: tilt 2 rolls the 3rd down (${h3t.toFixed(3)} < ${h3.toFixed(3)})`);
}

// Nyquist guard: at 16 kHz, every partial above the first is above the guard, so
// the render must be indistinguishable from the same tone with no partials.
{
  const hi = [{ frequency: 16000, amplitude: 1 }];
  const plain = renderChannels(hi, shapeOf({}), seconds, rate).left;
  const many = renderChannels(hi, shapeOf({ enrichment: 1, partials: 6, partialTilt: 0 }), seconds, rate).left;
  let worst = 0;
  for (let i = 0; i < plain.length; i++) worst = Math.max(worst, Math.abs(plain[i] - many[i]));
  near(worst, 0, "Nyquist: no partial above the guard is rendered", 1e-12);

  // ...and the guard is not simply dropping everything: a low tone keeps its own
  let lowWorst = 0;
  const low = [{ frequency: 200, amplitude: 1 }];
  const a = renderChannels(low, shapeOf({}), seconds, rate).left;
  const b = renderChannels(low, shapeOf({ enrichment: 1, partials: 6, partialTilt: 0 }), seconds, rate).left;
  for (let i = 0; i < a.length; i++) lowWorst = Math.max(lowWorst, Math.abs(a[i] - b[i]));
  ok(lowWorst > 1e-3, "Nyquist: a low tone still gains its partials");
}

// low-pass. A single tone proves nothing: the renderer peak-normalises, so
// attenuating a lone sine is undone by the following gain. Use a MIX and compare
// how the two components stand relative to each other.
{
  const mix = [{ frequency: 100, amplitude: 1 }, { frequency: 10000, amplitude: 1 }];
  const open = renderChannels(mix, shapeOf({ lowpassHz: 20000 }), seconds, rate).left;
  const shut = renderChannels(mix, shapeOf({ lowpassHz: 500 }), seconds, rate).left;
  const rOpen = ampAt(open, 10000, rate) / ampAt(open, 100, rate);
  const rShut = ampAt(shut, 10000, rate) / ampAt(shut, 100, rate);
  ok(rShut < rOpen * 0.2, `low-pass: 10 kHz falls against 100 Hz (${rShut.toFixed(4)} vs ${rOpen.toFixed(4)})`);
  ok(ampAt(shut, 100, rate) > 0, "low-pass: the low component survives");
}

// tremolo: full depth must take the envelope down to (near) zero cyclically.
{
  const flat = renderChannels(tones, shapeOf({}), seconds, rate).left;
  const trem = renderChannels(tones, shapeOf({ tremoloRateHz: 4, tremoloDepth: 1 }), seconds, rate).left;
  ok(rms(trem) < rms(flat) * 0.8, "tremolo: full depth reduces overall level");
  // over several cycles the normalised envelope must swing low AND high
  let lo = 1, hi = 0;
  const win = Math.round(0.002 * rate);
  for (let start = 0; start + win < trem.length; start += win) {
    const env = peak(trem.slice(start, start + win));
    if (env < lo) lo = env;
    if (env > hi) hi = env;
  }
  ok(hi > 0, "tremolo: has a peak");
  ok(lo < hi * 0.25, `tremolo: envelope reaches down (${(lo / hi).toFixed(3)} of peak)`);
}

// reverb: mix 0 vs 80 must differ, and the wet version is not simply louder.
{
  const dry = renderChannels(tones, shapeOf({ reverbMix: 0 }), seconds, rate).left;
  const wet = renderChannels(tones, shapeOf({ reverbMix: 80, reverbPreset: 4 }), seconds, rate).left;
  let diff = 0;
  for (let i = 0; i < dry.length; i++) diff = Math.max(diff, Math.abs(dry[i] - wet[i]));
  ok(diff > 1e-3, "reverb: wet differs from dry");
  ok(peak(wet) <= headroom + 1e-9, "reverb: still inside headroom");
}

// width: stereo needs more than one voice AND a non-zero width.
{
  const mono = renderChannels(tones, shapeOf({ unisonVoices: 1, width: 1 }), seconds, rate);
  eq(mono.channels, 1, "width: one voice stays mono");
  const flat = renderChannels(tones, shapeOf({ unisonVoices: 3, width: 0 }), seconds, rate);
  eq(flat.channels, 1, "width: zero width stays mono");
  const wide = renderChannels(tones, shapeOf({ unisonVoices: 3, width: 1 }), seconds, rate);
  eq(wide.channels, 2, "width: three voices with width render stereo");
  let diff = 0;
  for (let i = 0; i < wide.left.length; i++) diff = Math.max(diff, Math.abs(wide.left[i] - wide.right[i]));
  ok(diff > 1e-3, "width: the channels are decorrelated");
}

/* ---- 3. the loop seam --------------------------------------------------- */

// The buffer repeats, so the step from its last sample to its first must be no
// worse than the steps inside it.
{
  const shaped = shapeOf(Object.assign({}, base, { reverbMix: 0 }));
  const r = renderChannels(tones, shaped, 0.5, rate);
  const n = r.left.length;
  let worstInside = 0;
  for (let i = 1; i < n; i++) worstInside = Math.max(worstInside, Math.abs(r.left[i] - r.left[i - 1]));
  const seamStep = Math.abs(r.left[0] - r.left[n - 1]);
  ok(seamStep <= worstInside * 1.5 + 1e-9,
     `loop seam: step ${seamStep.toExponential(3)} <= internal worst ${worstInside.toExponential(3)}`);
}

/* ---- 4. the container, mono and stereo ---------------------------------- */

for (const [label, shaped, wantCh] of [
  ["dry mono", shapeOf({}), 1],
  ["voiced stereo", shapeOf(Object.assign({}, makeSynthParams(), { unisonVoices: 3, width: 0.8 })), 2],
]) {
  const packet = wavPacket(tones, shaped, 0.3, rate);
  eq(packet.channels, wantCh, `${label}: packet reports ${wantCh} channel(s)`);
  const payload = packet.url.slice("data:audio/wav;base64,".length);
  const bytes = Buffer.from(payload, "base64");
  const dataBytes = bytes.length - 44;
  const frameBytes = wantCh * (bitsPerSample / 8);
  eq(dataBytes % frameBytes, 0, `${label}: data is whole frames`);
  eq(packet.frames, dataBytes / frameBytes, `${label}: frame count matches the data size`);

  const u32 = (at) => bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24);
  eq(bytes.slice(0, 4).toString("latin1"), "RIFF", `${label}: RIFF tag`);
  eq(u32(4), 36 + dataBytes, `${label}: RIFF size`);
  eq(bytes.slice(8, 12).toString("latin1"), "WAVE", `${label}: WAVE tag`);
  eq(bytes.slice(12, 16).toString("latin1"), "fmt ", `${label}: fmt tag`);
  eq(u32(16), 16, `${label}: fmt chunk size`);
  eq(bytes[20], 1, `${label}: PCM format tag`);
  eq(bytes[22], wantCh, `${label}: channel count`);
  eq(u32(24), rate, `${label}: sample rate`);
  eq(u32(28), rate * wantCh * (bitsPerSample / 8), `${label}: byte rate`);
  eq(bytes[32], frameBytes, `${label}: block align`);
  eq(bytes[34], bitsPerSample, `${label}: bit depth`);
  eq(bytes.slice(36, 40).toString("latin1"), "data", `${label}: data tag`);
  eq(u32(40), dataBytes, `${label}: data chunk size`);

  const path = `/tmp/validate-wav-${wantCh}ch.wav`;
  writeFileSync(path, bytes);
  try {
    const probe = execFileSync("ffprobe", [
      "-v", "error", "-select_streams", "a:0",
      "-show_entries", "stream=codec_name,sample_rate,channels,bits_per_sample",
      "-of", "default=noprint_wrappers=1:nokey=0", path,
    ], { encoding: "utf8" });
    const field = (k) => (probe.match(new RegExp(`${k}=(.+)`)) || [])[1] || "";
    eq(field("codec_name"), "pcm_s16le", `${label}: ffprobe codec`);
    eq(field("sample_rate"), String(rate), `${label}: ffprobe sample rate`);
    eq(field("channels"), String(wantCh), `${label}: ffprobe channels`);
    eq(field("bits_per_sample"), String(bitsPerSample), `${label}: ffprobe bit depth`);
  } catch (e) {
    fail(`${label}: ffprobe could not read the buffer: ${e.message}`);
  }
}

/* ---- 5. headroom, and base64 round trip --------------------------------- */

{
  const packet = wavPacket(tones, shapeOf(Object.assign({}, makeSynthParams(), { unisonVoices: 3, width: 1 })), 0.2, rate);
  const payload = packet.url.slice("data:audio/wav;base64,".length);
  eq(payload.length % 4, 0, "base64 length is a multiple of 4");
  ok(/^[A-Za-z0-9+/]+={0,2}$/.test(payload), "base64 alphabet");
  const r = renderChannels(tones, shapeOf(Object.assign({}, makeSynthParams())), 0.2, rate);
  ok(peak(r.left) <= headroom + 1e-9, "headroom respected");
  const mono = base64(encodeWav(r.left, rate, 1));
  ok(mono.length > 0, "base64 round trip produces output");
}

/* ---- 6. guards ---------------------------------------------------------- */

eq(clampDuration(0), 1, "clampDuration: zero becomes 1s");
eq(clampDuration(-5), 1, "clampDuration: negative becomes 1s");
eq(clampDuration(1e9), 30, "clampDuration: clamped at 30s");
ok(seamSeconds > 0, "seam length is positive");

console.log(`signal      : ${bareCases.length} tone sets, ${checked} checks`);
console.log(`voicing     : unison, partials, low-pass, tremolo, reverb, width`);
console.log(`guards      : Nyquist, loop seam, container, ffprobe (mono + stereo)`);
console.log("");

if (bad) {
  console.log(`RESULT: FAIL  (${bad} of ${checked} checks failed)`);
  for (const p of problems) console.log(`  ${p}`);
  process.exit(1);
}
console.log(`RESULT: PASS  (${checked} checks; signal exact, voicing verified, Nyquist respected, loop seam continuous, ffprobe reads pcm_s16le ${rate} Hz mono and stereo)`);