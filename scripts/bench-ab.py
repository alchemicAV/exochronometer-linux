#!/usr/bin/env python3
"""A/B the two harnesses that disagree on identical configuration.

  A: write main-p3.qml into build/app and run it there   (what measure-pages does)
  B: copy the app to /tmp and run main.qml there          (what bench-* do)

Same page (3 = MISC, default mode PHASE), same refresh rate. If A and B differ,
the harness is measuring different things and every number needs re-checking.
"""
import os, shutil, signal, subprocess, time, glob, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exoab"


def ticks(pid):
    p = open(f"/proc/{pid}/stat").read().split()
    return int(p[13]) + int(p[14])


def sample(pid, seconds=6.0):
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(seconds)
    t1 = ticks(pid); w1 = time.time()
    return (t1 - t0) / hz / (w1 - w0) * 100.0


def focus():
    try:
        raw = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, timeout=10).stdout
        for c in json.loads(raw):
            if c.get("title") == "Exochronometer":
                subprocess.run(["hyprctl", "dispatch", "focuswindow", "address:" + c["address"]],
                               capture_output=True, timeout=10)
    except Exception:
        pass


def find_pid(marker):
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        except OSError:
            continue
        if "qml" in cmd and marker in cmd:
            return int(os.path.basename(d))
    return None


def run(label, cwd, qmlfile, marker):
    p = subprocess.Popen(["qml6", qmlfile], cwd=cwd,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5.5)
    focus(); time.sleep(1.2)
    pid = find_pid(marker)
    if not pid:
        print(f"  {label:28s} FAILED TO START"); p.kill(); p.wait(); return
    print(f"  {label:28s} cpu {sample(pid):6.1f}%   (pid {pid})")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    time.sleep(1.5)


src = open(os.path.join(APP, "main.qml")).read()
p3 = src.replace("property int page: 0", "property int page: 3", 1)
open(os.path.join(APP, "main-p3.qml"), "w").write(p3)

if os.path.exists(TMP):
    shutil.rmtree(TMP)
shutil.copytree(APP, TMP)

for rep in (1, 2):
    print(f"round {rep}")
    run("A build/app main-p3.qml", APP, "main-p3.qml", "main-p3.qml")
    run("B /tmp copy main.qml", TMP, "main.qml", "main.qml")

os.remove(os.path.join(APP, "main-p3.qml"))
shutil.rmtree(TMP, ignore_errors=True)