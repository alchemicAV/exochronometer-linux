#!/usr/bin/env python3
"""Cheaper ways to draw the phase curve, measured with long repeated windows.

The single ctx.stroke() of the curve is the app's heaviest operation. Short
sampling windows landed on either side of a cliff, so each variant is measured
twice for 15 s and both numbers are reported.

  A  stroke, 400 points   (current)
  B  stroke, 200 points
  C  fillRect dots, 400 points  (no path stroking at all)
"""
import os, shutil, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exop"
base = open(os.path.join(APP, "main.qml")).read()
PAGE3 = base.replace("property int page: 0", "property int page: 3", 1)

STROKE_TAIL = """                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.beginPath()
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale
                    const y = cy - deriv[i] * dScale
                    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                }
                ctx.stroke()"""

DOTS_TAIL = """                ctx.fillStyle = color
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
        if "qml" in cmd and "main.qml" in cmd and "exop" in cwd:
            return int(os.path.basename(d))
    return None


def measure(name, mutate):
    if os.path.exists(TMP):
        shutil.rmtree(TMP)
    shutil.copytree(APP, TMP)
    open(os.path.join(TMP, "main.qml"), "w").write(PAGE3)
    p = os.path.join(TMP, "PhasePortraitView.qml")
    t = open(p).read()
    t2 = mutate(t)
    if t2 == t:
        print(f"  {name:18s} MUTATION DID NOT APPLY")
        shutil.rmtree(TMP, ignore_errors=True); return
    open(p, "w").write(t2)
    proc = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5.5)
    pid = find_pid()
    if not pid:
        print(f"  {name:18s} FAILED TO START"); proc.kill(); proc.wait(); return
    hz = os.sysconf("SC_CLK_TCK")
    out = []
    for _ in range(2):
        t0 = ticks(pid); w0 = time.time()
        time.sleep(15)
        t1 = ticks(pid); w1 = time.time()
        out.append((t1 - t0) / hz / (w1 - w0) * 100.0)
    print(f"  {name:18s} cpu {out[0]:6.1f}% / {out[1]:6.1f}%")
    proc.send_signal(signal.SIGTERM)
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill(); proc.wait()
    time.sleep(1.0)


measure("A stroke 400", lambda t: t)
measure("B stroke 200", lambda t: t.replace("const samples = 400", "const samples = 200"))
measure("C dots 400", lambda t: t.replace(STROKE_TAIL, DOTS_TAIL))
shutil.rmtree(TMP, ignore_errors=True)