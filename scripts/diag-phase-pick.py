#!/usr/bin/env python3
"""Pick a phase-curve primitive that is both faithful and affordable.

The trace is a wild criss-crossing mesh: the hour tones are 14-18.6 kHz, above
the 13.3 kHz Nyquist of an 800-sample/30 ms window, so consecutive samples jump
up to 680 px. The original strokes one 800-point Path; the port's truncated
stepped squares read as noise. Measure the alternatives at the real 5 Hz page
rate with two 12 s windows each.

  A  current: stepped squares, budget 4000   (truncates -> looks wrong)
  B  one ctx.stroke() of the whole path      (what the original does)
  C  one stroke per segment                  (faithful line, avoids long-path
                                              stroker cost)
  D  stepped squares, complete trace         (no truncation)
"""
import os, shutil, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exopick"
base = open(os.path.join(APP, "main.qml")).read()
PAGE3 = base.replace("property int page: 0", "property int page: 3", 1)

CURRENT = """                ctx.fillStyle = color
                let prevX = null, prevY = null
                let left = budget
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale
                    const y = cy - deriv[i] * dScale
                    if (prevX !== null && left > 0) {
                        const dx = x - prevX, dy = y - prevY
                        const span = Math.max(Math.abs(dx), Math.abs(dy))
                        const steps = Math.max(1, Math.ceil(span / 2))
                        for (let s = 1; s <= steps && left > 0; s++) {
                            ctx.fillRect(prevX + dx * (s / steps) - 1,
                                         prevY + dy * (s / steps) - 1, 2, 2)
                            left--
                        }
                    }
                    ctx.fillRect(x - 1, y - 1, 2, 2)
                    left--
                    prevX = x; prevY = y
                }"""

ONE_STROKE = """                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.beginPath()
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale
                    const y = cy - deriv[i] * dScale
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.stroke()"""

PER_SEGMENT = """                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                for (let i = 1; i < samples; i++) {
                    const x0 = cx + sigs[i - 1] * sScale
                    const y0 = cy - deriv[i - 1] * dScale
                    const x1 = cx + sigs[i] * sScale
                    const y1 = cy - deriv[i] * dScale
                    ctx.beginPath()
                    ctx.moveTo(x0, y0)
                    ctx.lineTo(x1, y1)
                    ctx.stroke()
                }"""

COMPLETE = CURRENT.replace("let left = budget", "let left = 200000")


def ticks(pid):
    p = open(f"/proc/{pid}/stat").read().split()
    return int(p[13]) + int(p[14])


def find_pid():
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
            cwd = os.readlink(os.path.join(d, "cwd"))
        except OSError:
            continue
        if "qml" in cmd and "main.qml" in cmd and "exopick" in cwd:
            return int(os.path.basename(d))
    return None


def measure(name, tail):
    if os.path.exists(TMP):
        shutil.rmtree(TMP)
    shutil.copytree(APP, TMP)
    open(os.path.join(TMP, "main.qml"), "w").write(PAGE3)
    p = os.path.join(TMP, "PhasePortraitView.qml")
    t = open(p).read()
    if tail is not None:
        if CURRENT not in t:
            print(f"  {name:14s} ANCHOR NOT FOUND")
            shutil.rmtree(TMP, ignore_errors=True); return
        open(p, "w").write(t.replace(CURRENT, tail, 1))
    proc = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(6)
    pid = find_pid()
    if not pid:
        print(f"  {name:14s} FAILED TO START"); proc.kill(); proc.wait(); return
    hz = os.sysconf("SC_CLK_TCK")
    out = []
    for _ in range(2):
        t0 = ticks(pid); w0 = time.time()
        time.sleep(12)
        t1 = ticks(pid); w1 = time.time()
        out.append((t1 - t0) / hz / (w1 - w0) * 100.0)
    print(f"  {name:14s} cpu {out[0]:6.1f}% / {out[1]:6.1f}%")
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill(); proc.wait()
    time.sleep(1.0)


measure("A current", None)
measure("B one stroke", ONE_STROKE)
measure("C per segment", PER_SEGMENT)
measure("D complete", COMPLETE)
shutil.rmtree(TMP, ignore_errors=True)