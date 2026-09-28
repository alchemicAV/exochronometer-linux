/**
 * Cross-validates the real-time C++ kernel against the JS one.
 *
 * The port has one rule: a numeric module is only trusted once something
 * independent agrees with it. The Swift oracle covers the instrument's maths, but
 * it cannot cover the audio kernel - AVFoundation exported no numbers - so the
 * two implementations of that kernel check each other instead:
 *
 *   src/audio/exosynth.cpp   what the sound card actually plays, via QAudioSink
 *   core/wavRender.ts        the offline renderer the rest of the suite covers
 *
 * They must agree sample for sample. If a partial, a filter, a delay length or a
 * pan law drifts in either one, this fails - which is the whole point, because
 * the real-time path is the one with no other coverage.
 *
 * src/audio/selftest.cpp links the kernel with no Qt at all and prints its inputs
 * alongside its output, so this file is data-driven: it recomputes whatever the
 * C++ side says it did, rather than repeating the cases by hand.
 *
 * Auto-gain is off and the voices are settled on the C++ side, so what is being
 * compared is the DSP itself and not the swell or the level tracking.
 */

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { renderKernel, expandVoices, sampleRate } from "../dist/core/wavRender.js";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const binary = join(root, "build", "audio", "exo-selftest");

if (!existsSync(binary)) {
  console.log("building the audio kernel first (scripts/build-audio.sh)...");
  try {
    execFileSync("bash", [join(root, "scripts", "build-audio.sh")], { stdio: "pipe" });
  } catch (e) {
    console.log("RESULT: FAIL  (could not build the C++ kernel)");
    console.log(String(e.stdout || "") + String(e.stderr || ""));
    process.exit(1);
  }
}

let checked = 0;
let bad = 0;
const problems = [];

function fail(what) {
  bad++;
  if (problems.length < 12) problems.push(what);
}

function ok(cond, what) {
  checked++;
  if (!cond) fail(what);
}

/** Absolute-plus-relative: float buffers against doubles never match exactly. */
function agrees(a, b, scale) {
  return Math.abs(a - b) <= 1e-5 + 2e-4 * scale;
}

let data;
try {
  data = JSON.parse(execFileSync(binary, { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }));
} catch (e) {
  console.log("RESULT: FAIL  (the kernel selftest did not run)");
  console.log(String(e.stderr || e.message).slice(0, 400));
  process.exit(1);
}

ok(data.rate === sampleRate, `sample rate matches (${data.rate} vs ${sampleRate})`);

for (const c of data.cases) {
  const tones = c.tones.map(([frequency, amplitude]) => ({ frequency, amplitude }));
  const shape = c.shape;
  const js = renderKernel(tones, shape, data.frames, data.rate);

  const label = c.name;

  // --- the expanded voice table: which frequencies, how loud, panned where ----
  // Compared entry for entry, in order. This is what caught a real bug: matching
  // a new bank against the sounding one by frequency ALONE merged two different
  // partials that happen to land on the same frequency (220 x 3 and 330 x 2 are
  // both 660 Hz), losing voices and halving their level.
  ok(js.left.length === data.frames, `${label}: JS rendered ${data.frames} frames`);
  const table = expandVoices(tones, shape, data.rate);
  ok(table.voices.length === c.voices.length,
     `${label}: voice count ${c.voices.length} (C++) vs ${table.voices.length} (JS)`);
  let worstVoice = "";
  const n = Math.min(table.voices.length, c.voices.length);
  for (let i = 0; i < n; i++) {
    const a = c.voices[i];
    const b = table.voices[i];
    if (Math.abs(a.f - b.frequency) > 1e-9 + 1e-12 * Math.abs(b.frequency)) {
      worstVoice = `[${i}] frequency ${a.f} vs ${b.frequency}`; break;
    }
    if (Math.abs(a.target - b.gain) > 1e-12) { worstVoice = `[${i}] gain ${a.target} vs ${b.gain}`; break; }
    if (Math.abs(a.gl - b.gainL) > 1e-12 || Math.abs(a.gr - b.gainR) > 1e-12) {
      worstVoice = `[${i}] pan ${a.gl}/${a.gr} vs ${b.gainL}/${b.gainR}`; break;
    }
    // phase is wrapped in C++ (fmod) and unwrapped in JS, so compare on the circle:
    // the difference taken modulo 2*pi, folded into [-pi, pi].
    let dp = (a.phase - b.phase) % (2 * Math.PI);
    if (dp > Math.PI) dp -= 2 * Math.PI;
    if (dp < -Math.PI) dp += 2 * Math.PI;
    if (Math.abs(dp) > 1e-9) { worstVoice = `[${i}] phase ${a.phase} vs ${b.phase}`; break; }
  }
  ok(worstVoice === "", `${label}: voice tables agree${worstVoice ? " - " + worstVoice : ""}`);

  // --- the samples ---------------------------------------------------------
  let scale = 0;
  for (const v of c.left) scale = Math.max(scale, Math.abs(v));
  let worstLeft = 0;
  for (let i = 0; i < data.frames; i++) {
    const d = Math.abs(c.left[i] - js.left[i]);
    if (d > worstLeft) worstLeft = d;
  }
  ok(worstLeft <= 1e-5 + 2e-4 * scale, `${label}: left channel agrees (worst ${worstLeft.toExponential(3)}, scale ${scale.toFixed(3)})`);

  let worstRight = 0;
  for (let i = 0; i < data.frames; i++) {
    const d = Math.abs(c.right[i] - js.right[i]);
    if (d > worstRight) worstRight = d;
  }
  ok(worstRight <= 1e-5 + 2e-4 * scale, `${label}: right channel agrees (worst ${worstRight.toExponential(3)})`);

  // Channel identity is itself a property: a mono render must be identical in
  // both channels, and a spread one must not be.
  let channelGap = 0;
  for (let i = 0; i < data.frames; i++) {
    channelGap = Math.max(channelGap, Math.abs(c.left[i] - c.right[i]));
  }
  if (c.voices.length > 0 && shape.unisonVoices > 1 && shape.width > 0.001) {
    ok(channelGap > 1e-4, `${label}: a spread render is actually stereo (gap ${channelGap.toExponential(3)})`);
  }
}

const names = data.cases.map((c) => c.name).join(", ");
console.log(`kernel      : C++ ${binary.replace(root + "/", "")} vs core/wavRender.ts`);
console.log(`cases       : ${names}`);
console.log(`compared    : ${data.frames} frames x 2 channels per case`);
console.log("");

if (bad) {
  console.log(`RESULT: FAIL  (${bad} of ${checked} checks failed)`);
  for (const p of problems) console.log(`  ${p}`);
  process.exit(1);
}
console.log(`RESULT: PASS  (${checked} checks; the real-time kernel and the offline renderer agree)`);