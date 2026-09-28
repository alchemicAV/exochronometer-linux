#!/usr/bin/env python3
"""What is MISC actually doing?

Halving the page refresh rate (10 Hz -> 5 Hz) did not change MISC's CPU at all,
so its cost is not the snapshot-driven repaint. Publish the PhasePortraitView
paint count AND the canvas size in the window title to tell apart:
  - paints/s far above the page rate  -> something else is driving requestPaint
  - paints/s at the page rate, huge canvas -> each paint is simply expensive
  - zero paints yet high CPU          -> the cost is not in the canvas at all
"""
import os, shutil, signal, subprocess, time, glob, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exodiag"

if os.path.exists(TMP):
    shutil.rmtree(TMP)
shutil.copytree(APP, TMP)

body = open(os.path.join(APP, "main.qml")).read()
body = body.replace("property int page: 0", "property int page: 3", 1)
open(os.path.join(TMP, "main.qml"), "w").write(body)

p = os.path.join(TMP, "PhasePortraitView.qml")
t = open(p).read()
t = t.replace("""    property bool live: true""",
"""    property bool live: true
    property int paints: 0

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            portrait.Window.window.title =
                "paints=" + portrait.paints +
                " canvas=" + Math.round(canvas.width) + "x" + Math.round(canvas.height)
            portrait.paints = 0
        }
    }""", 1)
t = t.replace("""        onPaint: {
            const ctx = getContext("2d")""",
"""        onPaint: {
            portrait.paints++
            const ctx = getContext("2d")""", 1)
open(p, "w").write(t)

proc = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(7)

def read_title():
    try:
        raw = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, timeout=10).stdout
        for c in json.loads(raw):
            if (c.get("title") or "").startswith("paints="):
                return c["title"], c.get("size")
    except Exception as e:
        return ("err " + str(e), None)
    return (None, None)

for _ in range(4):
    time.sleep(1.5)
    print("  ", read_title())

pid = None
for d in glob.glob("/proc/[0-9]*"):
    try:
        cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        cwd = os.readlink(os.path.join(d, "cwd"))
    except OSError:
        continue
    if "qml" in cmd and "main.qml" in cmd and "exodiag" in cwd:
        pid = int(os.path.basename(d)); break
if pid:
    st = open(f"/proc/{pid}/stat").read().split()
    a = int(st[13]) + int(st[14]); w0 = time.time()
    time.sleep(5)
    st = open(f"/proc/{pid}/stat").read().split()
    b = int(st[13]) + int(st[14]); w1 = time.time()
    print(f"   cpu {(b - a) / os.sysconf('SC_CLK_TCK') / (w1 - w0) * 100.0:.1f}%")

# Thread breakdown: which thread is burning it?
if pid:
    out = subprocess.run(["ps", "-T", "-p", str(pid), "-o", "tid,pcpu,comm",
                          "--no-headers"], capture_output=True, text=True).stdout
    print("   threads (pcpu is lifetime avg):")
    for line in out.splitlines()[:6]:
        print("     ", line.strip())

proc.send_signal(signal.SIGTERM)
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill(); proc.wait()
shutil.rmtree(TMP, ignore_errors=True)