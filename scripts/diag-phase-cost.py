#!/usr/bin/env python3
"""Which call inside PhasePortraitView's paint costs the time?

CPU is ~100% while the canvas paints about once a second, so a single paint is
pathologically expensive. Isolate the culprit by ablation (page 3 = MISC,
default mode PHASE):
    as-is        baseline
    few-samples  800 -> 100 points in the stroked path
    no-stroke    build the path but never stroke it
    no-curve     skip the curve entirely (axes only)
    no-axes      skip the crosshair axes
"""
import os, shutil, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exoc"
base = open(os.path.join(APP, "main.qml")).read()
PAGE3 = base.replace("property int page: 0", "property int page: 3", 1)


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
        if "qml" in cmd and "main.qml" in cmd and "exoc" in cwd:
            return int(os.path.basename(d))
    return None


def measure(name, mutate=None):
    if os.path.exists(TMP):
        shutil.rmtree(TMP)
    shutil.copytree(APP, TMP)
    open(os.path.join(TMP, "main.qml"), "w").write(PAGE3)
    if mutate:
        p = os.path.join(TMP, "PhasePortraitView.qml")
        t = open(p).read()
        t2 = mutate(t)
        if t2 == t:
            print(f"  {name:12s} MUTATION DID NOT APPLY"); shutil.rmtree(TMP, ignore_errors=True); return
        open(p, "w").write(t2)
    p = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5.5)
    pid = find_pid()
    if not pid:
        print(f"  {name:12s} FAILED TO START"); p.kill(); p.wait(); return
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(5)
    t1 = ticks(pid); w1 = time.time()
    print(f"  {name:12s} cpu {(t1 - t0) / hz / (w1 - w0) * 100.0:6.1f}%")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    time.sleep(1.0)


FEW = lambda t: t.replace("const samples = 800", "const samples = 100")

NO_STROKE = lambda t: t.replace("""                ctx.stroke()
            }

            if (!portrait.normalized) {""",
"""                if (false) ctx.stroke()
            }

            if (!portrait.normalized) {""")

NO_CURVE = lambda t: t.replace("""            if (!portrait.normalized) {
                drawCurve(tones, portrait.dayWindowSeconds, "rgba(255,255,255,0.85)", 1)""",
"""            if (!portrait.normalized) {
                if (false) drawCurve(tones, portrait.dayWindowSeconds, "rgba(255,255,255,0.85)", 1)""")

NO_AXES = lambda t: t.replace("""            ctx.beginPath()
            ctx.moveTo(cx - r, cy); ctx.lineTo(cx + r, cy)
            ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r)
            ctx.stroke()""",
"""            if (false) { ctx.beginPath()
            ctx.moveTo(cx - r, cy); ctx.lineTo(cx + r, cy)
            ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r)
            ctx.stroke() }""")

measure("as-is")
measure("few-samples", FEW)
measure("no-stroke", NO_STROKE)
measure("no-curve", NO_CURVE)
measure("no-axes", NO_AXES)
shutil.rmtree(TMP, ignore_errors=True)