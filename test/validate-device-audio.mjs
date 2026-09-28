/**
 * Regression test for the bug that produced "extremely choppy" audio.
 *
 * readData() wrote 16-bit samples into a stream the sink had declared Int32, so
 * the sink consumed this device twice as fast as it should, starved, and played
 * roughly half of every 46 ms as silence - periodic dropouts that sound like a
 * buffering problem and are really a format one.
 *
 * Nothing else in the suite could see it. The kernel cross-check compares the
 * synthesis, the envelope reproduction compares the kernel, the readouts report
 * counters - and every one of them was clean while the device was being fed
 * half-rate data. The only thing that catches it is measuring what the SOUND
 * DEVICE actually plays.
 *
 * Both hosts are checked, because both play through the same module: the standalone
 * app (via qml6) and the toolbar panel's host, Quickshell. A fix that only landed
 * in one of them would pass a single-host test and still be broken in the panel.
 *
 * Skips (exit 77) when there is no audio output, or when a host is unavailable.
 */

import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync, rmSync } from "node:fs";

const REPO = `${process.env.HOME}/exochronometer-linux`;
const MODULE_DIR = `${REPO}/build/audio`;
const CAPTURE = "/tmp/validate-device-audio.wav";
const SKIP = 77;
const skipAll = [];

function skip(reason) {
  console.log(`RESULT: SKIP (${reason})`);
  process.exit(SKIP);
}

// --- can we even test here? -------------------------------------------------
let sink = "";
try {
  sink = execFileSync("pactl", ["get-default-sink"], { encoding: "utf8" }).trim();
} catch { /* handled below */ }
if (!sink) skip("no audio output (pactl could not find a default sink)");
if (!existsSync(`${MODULE_DIR}/ExoAudio/libexoaudio.so`)) {
  skip("real-time module not built (run scripts/build-audio.sh)");
}

const haveQml = Boolean(execFileSync("sh", ["-c", "command -v qml6 || true"], { encoding: "utf8" }).trim());
const haveQs = Boolean(execFileSync("sh", ["-c", "command -v qs || true"], { encoding: "utf8" }).trim());

/**
 * Play `args` while recording the sink's monitor, then measure exact-zero runs in
 * the capture. A synthesised signal is never exactly zero, so a zero run means the
 * audio stack delivered silence - not that the instrument went quiet.
 */
function measure(label, args, env, secs = 5) {
  rmSync(CAPTURE, { force: true });
  const child = spawn(args[0], args.slice(1), { env, stdio: "ignore" });
  return new Promise((resolve) => {
    setTimeout(() => {
      const rec = spawn("timeout", [String(secs + 3), "parec", "-d", `${sink}.monitor`,
        "--rate=48000", "--channels=2", "--format=s16le", "--file-format=wav", CAPTURE],
        { stdio: "ignore" });
      rec.on("exit", () => {
        child.kill("SIGKILL");
        if (!existsSync(CAPTURE)) return resolve(null);
        const buf = readFileSync(CAPTURE);
        const rate = buf.readUInt32LE(24);
        const channels = buf.readUInt16LE(22);
        const start = buf.indexOf("data") + 8;
        const frames = Math.floor((buf.length - start) / (2 * channels));
        const from = Math.floor(0.7 * rate);            // ignore the recorder's start
        let run = 0, worst = 0, silent = 0, any = false;
        for (let i = from; i < frames; i++) {
          if (buf.readInt16LE(start + i * 2 * channels) === 0) {
            run++; silent++; if (run > worst) worst = run;
          } else { run = 0; any = true; }
        }
        const analysed = frames - from;
        resolve({
          label, seconds: frames / rate, anySound: any,
          worstMs: (worst / rate) * 1000,
          pct: analysed > 0 ? (silent / analysed) * 100 : 100,
        });
      });
    }, 2500);
  });
}

const env = { ...process.env, QML_IMPORT_PATH: MODULE_DIR };
const results = [];

if (haveQml) {
  results.push(await measure("app host (qml6)",
    ["timeout", "14", "qml6", `${REPO}/test/device-probe.qml`], env));
} else {
  skipAll.push("app host (qml6 not installed)");
}

if (haveQs) {
  results.push(await measure("toolbar host (Quickshell)",
    ["timeout", "20", "qs", "--path", `${REPO}/test/quickshell-probe`], env));
} else {
  skipAll.push("toolbar host (qs not installed)");
}

const checks = [];
const ok = (good, label) => checks.push({ good: Boolean(good), label });
console.log(`device       : ${sink}`);
const counted = [];
for (const r of results) {
  if (!r) { ok(false, "a host produced no recording"); continue; }
  if (!r.anySound) { skipAll.push(`${r.label}: no sound here`); continue; }
  counted.push(r);
  console.log(`host         : ${r.label}`);
  console.log(`  captured   : ${r.seconds.toFixed(2)} s`);
  ok(r.worstMs < 150, `${r.label}: longest silence gap ${r.worstMs.toFixed(1)} ms (< 150 ms)`);
  ok(r.pct < 2, `${r.label}: silence after the start ${r.pct.toFixed(2)}% (< 2%)`);
}
for (const s of skipAll) console.log(`skipped      : ${s}`);

if (checks.length === 0) skip("no host produced sound here (headless? no audio session?)");

const failed = checks.filter((c) => !c.good);
for (const c of checks) if (!c.good) console.log(`  FAIL ${c.label}`);
console.log(`RESULT: ${failed.length === 0 ? "PASS" : "FAIL"}  (${checks.length} checks over `
  + `${counted.length} host(s); silence `
  + `${counted.map((r) => r.pct.toFixed(2) + "%").join(" / ")})`);
process.exit(failed.length === 0 ? 0 : 1);