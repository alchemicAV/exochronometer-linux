#!/usr/bin/env python3
"""Measure CPU of the app on each page, one page per launch.

Every page is instantiated whether or not it is visible, so the honest question
is "what does each page cost" rather than "what does the app cost". This builds a
sibling main-pN.qml with `page: N` baked in, launches it, samples
utime+stime deltas from /proc, then kills it.
"""
import json, os, re, signal, subprocess, sys, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
PAGES = {0: "CIRCLES", 1: "PEAK CALENDAR", 2: "GEOMETRY HARMONICS",
         3: "MISC", 4: "TIMELINE", 5: "SPECTRUM"}


def ticks(pid):
    parts = open(f"/proc/{pid}/stat").read().split()
    return int(parts[13]) + int(parts[14])


def find_pid(marker):
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        except OSError:
            continue
        if marker in cmd:
            return int(os.path.basename(d))
    return None


def sample(pid, seconds):
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(seconds)
    t1 = ticks(pid); w1 = time.time()
    return (t1 - t0) / hz / (w1 - w0) * 100.0


def focus_exo():
    """Raise the app window before sampling.

    Qt throttles rendering for a window the compositor is not showing, which
    silently deflates CPU numbers (and, when hidden, can make each canvas
    repaint synchronous instead). Focusing makes the measurement comparable.
    """
    try:
        raw = subprocess.run(["hyprctl", "clients", "-j"],
                             capture_output=True, timeout=10).stdout
        for c in json.loads(raw):
            if c.get("title") == "Exochronometer":
                subprocess.run(["hyprctl", "dispatch", "focuswindow",
                                "address:" + c["address"]],
                               capture_output=True, timeout=10)
                return c.get("workspace", {}).get("name"), c.get("hidden")
    except Exception as e:
        return ("err", str(e))
    return (None, None)


src = open(os.path.join(APP, "main.qml")).read()
assert "property int page: 0" in src, "page default not found"

results = []
for n, name in PAGES.items():
    body = src.replace("property int page: 0", f"property int page: {n}", 1)
    target = os.path.join(APP, f"main-p{n}.qml")
    open(target, "w").write(body)

    p = subprocess.Popen(["qml6", f"main-p{n}.qml"], cwd=APP,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(4.5)                      # let it settle past startup
    ws, hidden = focus_exo()
    time.sleep(1.0)
    pid = find_pid(f"main-p{n}.qml")
    if not pid:
        print(f"page {n} {name:18s}  FAILED TO START")
        p.kill(); p.wait(); continue
    cpu = sample(pid, 12.0)
    rss = int([l for l in open(f"/proc/{pid}/status") if l.startswith("VmRSS")][0].split()[1]) / 1024
    results.append((n, name, cpu, rss))
    print(f"page {n} {name:18s}  cpu {cpu:6.1f}%   rss {rss:6.1f} MB   ws={ws} hidden={hidden}")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    os.remove(target)
    time.sleep(1.0)

if results:
    lo = min(results, key=lambda r: r[2])
    hi = max(results, key=lambda r: r[2])
    print()
    print(f"cheapest: page {lo[0]} {lo[1]} at {lo[2]:.1f}%")
    print(f"dearest : page {hi[0]} {hi[1]} at {hi[2]:.1f}%")
    print(f"spread  : {hi[2] - lo[2]:.1f} points")