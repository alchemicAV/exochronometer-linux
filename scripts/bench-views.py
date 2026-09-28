#!/usr/bin/env python3
"""Instantiate ONE Misc view at a time and measure its CPU.

MISC burns ~102% on the main thread while its canvas paints once a second, so
the cost is not the paint. Each view is loaded alone, live, with a real
snapshot, and measured -- which pinpoints the spinner.
"""
import os, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exoviews"
os.makedirs(TMP, exist_ok=True)
if not os.path.islink(os.path.join(TMP, "core")):
    os.symlink(os.path.join(APP, "core"), os.path.join(TMP, "core"))
for f in os.listdir(APP):
    if f.endswith(".qml"):
        src = os.path.join(APP, f)
        dst = os.path.join(TMP, f)
        if not os.path.exists(dst):
            os.symlink(src, dst)

VIEWS = ["PhasePortraitView", "CentsWheelView", "DissonanceMeters", "ChladniView",
         "SpectrogramView", "ConvergenceView", "ColorMappingView", "LissajousView",
         "SelectorView"]

HARNESS = '''import QtQuick
import QtQuick.Window
import "core/exoSnapshot.mjs" as Exo

Window {
    id: root
    width: 1180; height: 940
    visible: true
    color: "#0d0d11"
    title: "Exochronometer"

    property var snapshot: Exo.capture(new Date())
    property bool fundamentalsOff: true
    property var excluded: []

    Timer { interval: 200; running: true; repeat: true
            onTriggered: root.snapshot = Exo.capture(new Date()) }

    __NAME__ {
        anchors.fill: parent
        live: true
        snapshot: root.snapshot
        fundamentalsOff: root.fundamentalsOff
        excluded: root.excluded
    }
}
'''


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
        if "qml" in cmd and "one.qml" in cmd and "exoviews" in cwd:
            return int(os.path.basename(d))
    return None


for name in VIEWS:
    open(os.path.join(TMP, "one.qml"), "w").write(HARNESS.replace("__NAME__", name))
    p = subprocess.Popen(["qml6", "one.qml"], cwd=TMP,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5)
    pid = find_pid()
    if not pid:
        print(f"  {name:20s} FAILED TO START"); p.kill(); p.wait(); continue
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(5)
    t1 = ticks(pid); w1 = time.time()
    print(f"  {name:20s} cpu {(t1 - t0) / hz / (w1 - w0) * 100.0:6.1f}%")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    time.sleep(1.0)