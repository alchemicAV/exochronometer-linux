#!/usr/bin/env python3
"""Time ONE PhasePortraitView paint, with the instrumentation verified applied.

The main thread samples as: polishItems -> QPaintEngineEx::stroke ->
QRasterPaintEngine::fill, i.e. the Canvas is rasterised on the CPU. If a single
paint takes ~a second, then painting once per second is already 100% CPU and the
repaint rate is a red herring -- the paint itself is the problem.
"""
import os, shutil, signal, subprocess, time, glob, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exopt2"

if os.path.exists(TMP):
    shutil.rmtree(TMP)
shutil.copytree(APP, TMP)

body = open(os.path.join(APP, "main.qml")).read()
body = body.replace("property int page: 0", "property int page: 3", 1)
open(os.path.join(TMP, "main.qml"), "w").write(body)

p = os.path.join(TMP, "PhasePortraitView.qml")
t = open(p).read()
orig = t

# 1. counters + publish
old1 = "    property bool live: true"
new1 = """    property bool live: true
    property int paints: 0
    property real paintMs: 0
    property int samplesDrawn: 0

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            portrait.Window.window.title = "paints=" + portrait.paints +
                " ms=" + Math.round(portrait.paintMs) +
                " pts=" + portrait.samplesDrawn +
                " canvas=" + Math.round(canvas.width) + "x" + Math.round(canvas.height)
            portrait.paints = 0
            portrait.paintMs = 0
            portrait.samplesDrawn = 0
        }
    }"""
assert old1 in t, "counter anchor missing"
t = t.replace(old1, new1, 1)

# 2. time the paint -- anchor on the real first line of onPaint
old2 = """        onPaint: {
            const ctx = getContext("2d")"""
assert old2 in t, "onPaint anchor missing"
t = t.replace(old2, """        onPaint: {
            const t0 = Date.now()
            portrait.paints++
            const ctx = getContext("2d")""", 1)

# 3. close the timing at the last statement of the paint
old3 = """                    drawCurve(group, portrait.normalizedWindowSeconds(tf),
                              portrait.colOf(HC.blendedColor(group)), 0.9)
                }
            }
        }
    }"""
assert old3 in t, "paint-tail anchor missing"
t = t.replace(old3, """                    drawCurve(group, portrait.normalizedWindowSeconds(tf),
                              portrait.colOf(HC.blendedColor(group)), 0.9)
                }
            }
            portrait.paintMs += Date.now() - t0
        }
    }""", 1)

# 4. count the points pushed into the stroked path
old4 = """                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale"""
assert old4 in t, "path anchor missing"
t = t.replace(old4, """                portrait.samplesDrawn += samples
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale""", 1)

assert t != orig
open(p, "w").write(t)
print("instrumentation applied (all 4 anchors verified)")

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
    time.sleep(1.5)
    print("  ", read_title())

pid = None
for d in glob.glob("/proc/[0-9]*"):
    try:
        cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        cwd = os.readlink(os.path.join(d, "cwd"))
    except OSError:
        continue
    if "qml" in cmd and "main.qml" in cmd and "exopt2" in cwd:
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