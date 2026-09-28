#!/usr/bin/env python3
"""What drives PhasePortraitView's continuous repaint?

Variants (all page 3 = MISC, default mode PHASE):
  as-is        - baseline
  no-conn      - the snapshot->requestPaint handler removed (paints once only)
  no-canvas    - the Canvas deleted entirely (surrounding QML still built)
  no-timer     - the page clock stopped (snapshot never changes)

If no-conn fixes it, the repaint is driven by snapshot changes and something is
changing the snapshot far more often than the page rate. If no-canvas fixes it
while no-conn does not, the Canvas repaints itself (e.g. a size feedback loop).
"""
import os, shutil, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exov"
base = open(os.path.join(APP, "main.qml")).read()
assert "property int page: 0" in base
PAGE3 = base.replace("property int page: 0", "property int page: 3", 1)


def variant(name, mutate=None):
    if os.path.exists(TMP):
        shutil.rmtree(TMP)
    shutil.copytree(APP, TMP)
    open(os.path.join(TMP, "main.qml"), "w").write(PAGE3)
    if mutate:
        p = os.path.join(TMP, "PhasePortraitView.qml")
        t = open(p).read()
        t2 = mutate(t)
        assert t2 != t, f"{name}: mutation did not apply"
        open(p, "w").write(t2)


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
        if "qml" in cmd and "main.qml" in cmd and "exov" in cwd:
            return int(os.path.basename(d))
    return None


def measure(name, mutate=None):
    variant(name, mutate)
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


NO_CONN = lambda t: t.replace("""        Connections {
            target: portrait
            // Only the displayed view repaints; a hidden Canvas still runs
            // onPaint when requestPaint() is called on it.
            function onSnapshotChanged() {
                if (portrait.live) canvas.requestPaint()
            }
        }
""", "")

NO_CANVAS = lambda t: t.replace("""    Canvas {
        id: canvas
        anchors.fill: parent
""", """    Item {
        id: canvas
        anchors.fill: parent
        visible: false
""")

NO_TIMER = None  # handled at the main.qml level

measure("as-is")
measure("no-conn", NO_CONN)
measure("no-canvas", NO_CANVAS)

# no-timer: stop the page clock in main.qml
if os.path.exists(TMP):
    shutil.rmtree(TMP)
shutil.copytree(APP, TMP)
t = PAGE3.replace("""        if (page === 3) return 200                     // misc: slow readouts""",
                  """        if (page === 3) return 0""", 1)
assert t != PAGE3
open(os.path.join(TMP, "main.qml"), "w").write(t)
p = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(5.5)
pid = find_pid()
if pid:
    hz = os.sysconf("SC_CLK_TCK")
    a = ticks(pid); w0 = time.time(); time.sleep(5); b = ticks(pid); w1 = time.time()
    print(f"  {'no-timer':12s} cpu {(b - a) / hz / (w1 - w0) * 100.0:6.1f}%")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
shutil.rmtree(TMP, ignore_errors=True)