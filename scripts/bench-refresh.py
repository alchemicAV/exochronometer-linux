#!/usr/bin/env python3
"""Isolate what drives the app's CPU by re-timing the global refresh timer.

Every page measured ~101%, which means the cost is not page-specific. The
suspect is the global 15 Hz `refresh()` timer: it replaces `root.snapshot`, and
every view's `Connections { onSnapshotChanged }` reacts -- including views that
are `visible: false`, because invisibility stops *rendering*, not binding
evaluation.

Variants:
  base    - as shipped (15 Hz refresh + 1 Hz resnap)
  slow2   - refresh at 2 Hz
  slow1   - refresh at 1 Hz
  frozen  - refresh timer stopped entirely (snapshot never changes)
"""
import os, re, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
src = open(os.path.join(APP, "main.qml")).read()

# The refresh timer is the one triggering root.refresh().
REFRESH_BLOCK = """    Timer {
        interval: 1000 / 15
        running: true
        repeat: true
        onTriggered: root.refresh()
    }"""
assert REFRESH_BLOCK in src, "refresh timer block not found verbatim"


def variant(name, block):
    body = src.replace(REFRESH_BLOCK, block, 1)
    path = os.path.join(APP, f"main-bench-{name}.qml")
    open(path, "w").write(body)
    return path


VARIANTS = {
    "base":   REFRESH_BLOCK,
    "slow2":  REFRESH_BLOCK.replace("1000 / 15", "500"),
    "slow1":  REFRESH_BLOCK.replace("1000 / 15", "1000"),
    "frozen": REFRESH_BLOCK.replace("running: true", "running: false"),
}


def ticks(pid):
    p = open(f"/proc/{pid}/stat").read().split()
    return int(p[13]) + int(p[14])


def find_pid(marker):
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        except OSError:
            continue
        if marker in cmd:
            return int(os.path.basename(d))
    return None


for name, block in VARIANTS.items():
    path = variant(name, block)
    p = subprocess.Popen(["qml6", os.path.basename(path)], cwd=APP,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(4.5)
    pid = find_pid(os.path.basename(path))
    if not pid:
        print(f"{name:8s} FAILED TO START")
        p.kill(); p.wait(); os.remove(path); continue
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(6.0)
    t1 = ticks(pid); w1 = time.time()
    cpu = (t1 - t0) / hz / (w1 - w0) * 100.0
    print(f"{name:8s} cpu {cpu:6.1f}%")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    os.remove(path)
    time.sleep(1.0)