#!/usr/bin/env python3
"""Is the long stroked path expensive because of its LENGTH, or because it is
one huge self-intersecting path?

Baseline: one ctx.stroke() of an 800-point self-intersecting orbit costs ~79% of
a core. A phase portrait scribble self-intersects heavily, and Qt's stroker does
intersection work per path. If the cost is per-path rather than per-point,
splitting the trace into short stroked runs should be cheap AND keep the
original continuous-line look.

  A  one long stroke            (baseline)
  B  chunks of 16 points        (50 strokes)
  C  one stroke per segment     (800 strokes)
  D  dots 2x2                   (current cheap fallback)
"""
import os, shutil, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exoch"
base = open(os.path.join(APP, "main.qml")).read()
PAGE3 = base.replace("property int page: 0", "property int page: 3", 1)

LONG = """                ctx.fillStyle = color
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale
                    const y = cy - deriv[i] * dScale
                    ctx.fillRect(x - 1.5, y - 1.5, 3, 3)
                }"""

CHUNK = """                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.beginPath()
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale
                    const y = cy - deriv[i] * dScale
                    if (i % 16 === 0) {
                        if (i > 0) ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(x, y)
                    } else {
                        ctx.lineTo(x, y)
                    }
                }
                ctx.stroke()"""

PERSEG = """                ctx.strokeStyle = color
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

DOTS = """                ctx.fillStyle = color
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale
                    const y = cy - deriv[i] * dScale
                    ctx.fillRect(x - 1, y - 1, 2, 2)
                }"""


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
        if "qml" in cmd and "main.qml" in cmd and "exoch" in cwd:
            return int(os.path.basename(d))
    return None


def measure(name, tail):
    if os.path.exists(TMP):
        shutil.rmtree(TMP)
    shutil.copytree(APP, TMP)
    open(os.path.join(TMP, "main.qml"), "w").write(PAGE3)
    p = os.path.join(TMP, "PhasePortraitView.qml")
    t = open(p).read()
    assert LONG in t, "baseline drawing block not found"
    open(p, "w").write(t.replace(LONG, tail, 1))
    proc = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5.5)
    pid = find_pid()
    if not pid:
        print(f"  {name:16s} FAILED TO START"); proc.kill(); proc.wait(); return
    hz = os.sysconf("SC_CLK_TCK")
    out = []
    for _ in range(2):
        t0 = ticks(pid); w0 = time.time()
        time.sleep(12)
        t1 = ticks(pid); w1 = time.time()
        out.append((t1 - t0) / hz / (w1 - w0) * 100.0)
    print(f"  {name:16s} cpu {out[0]:6.1f}% / {out[1]:6.1f}%")
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill(); proc.wait()
    time.sleep(1.0)


measure("A one stroke", """                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.beginPath()
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale
                    const y = cy - deriv[i] * dScale
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.stroke()""")
measure("B chunks of 16", CHUNK)
measure("C per segment", PERSEG)
measure("D dots 2x2", DOTS)
shutil.rmtree(TMP, ignore_errors=True)