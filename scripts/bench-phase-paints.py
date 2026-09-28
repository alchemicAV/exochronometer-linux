#!/usr/bin/env python3
"""Count PhasePortraitView paints per second.

PHASE burns ~101% CPU while every other mode is under 35%. Two very different
causes need distinguishing:
  (a) the paint is expensive but runs at the 10 Hz page rate, or
  (b) something is driving requestPaint in a tight loop.

Counting paints settles it. The count is mirrored into the window title because
console.log is silent in this Qt build.
"""
import os, shutil, signal, subprocess, time, glob, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exophase"

if os.path.exists(TMP):
    shutil.rmtree(TMP)
shutil.copytree(APP, TMP)

main = open(os.path.join(TMP, "main.qml")).read()
main = main.replace("property int page: 0", "property int page: 3", 1)
main = main.replace("""        visible: root.page === 3
        live: root.page === 3""",
                    """        visible: root.page === 3
        live: root.page === 3
        mode: 0""", 1)
open(os.path.join(TMP, "main.qml"), "w").write(main)

# Instrument the phase portrait: count paints, and publish the count in the
# window title once a second.
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
            portrait.Window.window.title = "paints/s=" + portrait.paints
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
time.sleep(6)

for i in range(4):
    time.sleep(1.2)
    try:
        raw = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, timeout=10).stdout
        for c in json.loads(raw):
            if "paints/s" in (c.get("title") or ""):
                print("  ", c["title"])
                break
    except Exception as e:
        print("  read failed:", e)

pid = None
for d in glob.glob("/proc/[0-9]*"):
    try:
        cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        cwd = os.readlink(os.path.join(d, "cwd"))
    except OSError:
        continue
    if "qml" in cmd and "main.qml" in cmd and "exophase" in cwd:
        pid = int(os.path.basename(d)); break
if pid:
    hz = os.sysconf("SC_CLK_TCK")
    t0 = open(f"/proc/{pid}/stat").read().split(); a = int(t0[13]) + int(t0[14]); w0 = time.time()
    time.sleep(5)
    t1 = open(f"/proc/{pid}/stat").read().split(); b = int(t1[13]) + int(t1[14]); w1 = time.time()
    print(f"   cpu {(b - a) / hz / (w1 - w0) * 100.0:.1f}%")

proc.send_signal(signal.SIGTERM)
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill(); proc.wait()
shutil.rmtree(TMP, ignore_errors=True)