#!/usr/bin/env python3
"""Time PhasePortraitView's paint and count its binding evaluations.

The view burns ~100% CPU while its canvas paints about once a second, so the
cost is elsewhere. Publish, once a second:
    paints  - onPaint calls
    ms      - total milliseconds spent inside onPaint
    tones   - liveTones re-evaluations
    closed  - isLoopClosed() calls (the "Total: Closed/Open" readout)
Whichever counter is huge is the culprit.
"""
import os, shutil, signal, subprocess, time, glob, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exotime"

if os.path.exists(TMP):
    shutil.rmtree(TMP)
shutil.copytree(APP, TMP)

body = open(os.path.join(APP, "main.qml")).read()
body = body.replace("property int page: 0", "property int page: 3", 1)
open(os.path.join(TMP, "main.qml"), "w").write(body)

p = os.path.join(TMP, "PhasePortraitView.qml")
t = open(p).read()

# counters + once-a-second publish
t = t.replace("""    property bool live: true""",
"""    property bool live: true
    property int paints: 0
    property real paintMs: 0
    property int toneEvals: 0
    property int closedEvals: 0

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            portrait.Window.window.title = "paints=" + portrait.paints +
                " ms=" + Math.round(portrait.paintMs) +
                " tones=" + portrait.toneEvals +
                " closed=" + portrait.closedEvals
            portrait.paints = 0
            portrait.paintMs = 0
            portrait.toneEvals = 0
            portrait.closedEvals = 0
        }
    }""", 1)

t = t.replace("""    readonly property var liveTones: {
        if (!live) return []""",
"""    readonly property var liveTones: {
        portrait.toneEvals++
        if (!live) return []""", 1)

t = t.replace("""        onPaint: {
            portrait.paints++
            const ctx = getContext("2d")""",
"""        onPaint: {
            const t0 = Date.now()
            portrait.paints++
            const ctx = getContext("2d")""", 1)

# close the timing at the end of onPaint: the last statement of the paint is the
# textBaseline reset.
t = t.replace("""                            ctx.textBaseline = "alphabetic"
                        }""",
"""                            ctx.textBaseline = "alphabetic"
                            portrait.paintMs += Date.now() - t0
                        }""", 1)

t = t.replace("""                const closed = PPM.isLoopClosed(tones, 0.030)""",
"""                portrait.closedEvals++
                const closed = PPM.isLoopClosed(tones, 0.030)""", 1)
open(p, "w").write(t)

proc = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(7)


def read_title():
    try:
        raw = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, timeout=10).stdout
        for c in json.loads(raw):
            if (c.get("title") or "").startswith("paints="):
                return c["title"]
    except Exception as e:
        return "err " + str(e)
    return None


for _ in range(5):
    time.sleep(1.4)
    print("  ", read_title())

pid = None
for d in glob.glob("/proc/[0-9]*"):
    try:
        cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        cwd = os.readlink(os.path.join(d, "cwd"))
    except OSError:
        continue
    if "qml" in cmd and "main.qml" in cmd and "exotime" in cwd:
        pid = int(os.path.basename(d)); break
if pid:
    st = open(f"/proc/{pid}/stat").read().split()
    a = int(st[13]) + int(st[14]); w0 = time.time()
    time.sleep(5)
    st = open(f"/proc/{pid}/stat").read().split()
    b = int(st[13]) + int(st[14]); w1 = time.time()
    print(f"   cpu {(b - a) / os.sysconf('SC_CLK_TCK') / (w1 - w0) * 100.0:.1f}%")

proc.send_signal(signal.SIGTERM)
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill(); proc.wait()
shutil.rmtree(TMP, ignore_errors=True)