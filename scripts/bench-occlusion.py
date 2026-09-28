#!/usr/bin/env python3
"""Does an occluded window cost MORE CPU than a focused one?

Two harnesses measured the same configuration 3x apart (34% vs 104%), and the
only environmental difference was which window was on top. Qt's Canvas may take
a synchronous repaint path when the window is not being rendered, which would
make an occluded window *more* expensive -- the opposite of intuition.

This measures one process twice: focused, then with another window raised over
it.
"""
import os, shutil, signal, subprocess, time, glob, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exooccl"


def ticks(pid):
    p = open(f"/proc/{pid}/stat").read().split()
    return int(p[13]) + int(p[14])


def sample(pid, seconds=6.0):
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(seconds)
    t1 = ticks(pid); w1 = time.time()
    return (t1 - t0) / hz / (w1 - w0) * 100.0


def clients():
    raw = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, timeout=10).stdout
    return json.loads(raw)


def find_pid():
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
            cwd = os.readlink(os.path.join(d, "cwd"))
        except OSError:
            continue
        if "qml" in cmd and "main.qml" in cmd and "exooccl" in cwd:
            return int(os.path.basename(d))
    return None


if os.path.exists(TMP):
    shutil.rmtree(TMP)
shutil.copytree(APP, TMP)
body = open(os.path.join(APP, "main.qml")).read()
body = body.replace("property int page: 0", "property int page: 3", 1)
open(os.path.join(TMP, "main.qml"), "w").write(body)

p = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(6)
pid = find_pid()
print("pid", pid)

# 1. focused / on top
for c in clients():
    if c.get("title") == "Exochronometer":
        subprocess.run(["hyprctl", "dispatch", "focuswindow", "address:" + c["address"]],
                       capture_output=True, timeout=10)
time.sleep(1.5)
print(f"  focused           cpu {sample(pid):6.1f}%")

# 2. raise some OTHER window over it
other = [c for c in clients() if c.get("title") != "Exochronometer"
         and c.get("mapped") and not c.get("hidden")]
if other:
    tgt = other[-1]
    subprocess.run(["hyprctl", "dispatch", "focuswindow", "address:" + tgt["address"]],
                   capture_output=True, timeout=10)
    print(f"  occluded by {tgt.get('title','?')[:40]!r}")
    time.sleep(1.5)
    print(f"  occluded          cpu {sample(pid):6.1f}%")

    # 3. and back again
    for c in clients():
        if c.get("title") == "Exochronometer":
            subprocess.run(["hyprctl", "dispatch", "focuswindow", "address:" + c["address"]],
                           capture_output=True, timeout=10)
    time.sleep(1.5)
    print(f"  focused again     cpu {sample(pid):6.1f}%")
else:
    print("  no other window available to occlude with")

p.send_signal(signal.SIGTERM)
try:
    p.wait(timeout=5)
except subprocess.TimeoutExpired:
    p.kill(); p.wait()
shutil.rmtree(TMP, ignore_errors=True)