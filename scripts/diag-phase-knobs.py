#!/usr/bin/env python3
"""Find a cheap way to draw the phase curve.

Ablation showed 100% of the cost is the single ctx.stroke() of the 800-point
curve; the surrounding JS is free. Test the practical knobs (page 3, mode PHASE):

    as-is           800 points, default AA
    s400            fewer points
    s200            fewer still
    aa-none         Qt's Context2D antialias off
    s400-aa-none    both
"""
import os, shutil, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exok"
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
        if "qml" in cmd and "main.qml" in cmd and "exok" in cwd:
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
            print(f"  {name:14s} MUTATION DID NOT APPLY")
            shutil.rmtree(TMP, ignore_errors=True); return
        open(p, "w").write(t2)
    p = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5.5)
    pid = find_pid()
    if not pid:
        print(f"  {name:14s} FAILED TO START"); p.kill(); p.wait(); return
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(5)
    t1 = ticks(pid); w1 = time.time()
    print(f"  {name:14s} cpu {(t1 - t0) / hz / (w1 - w0) * 100.0:6.1f}%")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    time.sleep(1.0)


S = lambda t, n: t.replace("const samples = 800", f"const samples = {n}")

AA = lambda t: t.replace("""                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.beginPath()""",
"""                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.antialias = "none"
                ctx.beginPath()""")

def both(t):
    return AA(S(t, 400))

measure("as-is")
measure("s400", lambda t: S(t, 400))
measure("s200", lambda t: S(t, 200))
measure("aa-none", AA)
measure("s400-aa-none", both)
shutil.rmtree(TMP, ignore_errors=True)