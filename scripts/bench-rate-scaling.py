#!/usr/bin/env python3
"""Measure MISC/PHASE CPU as a function of the page refresh rate.

If cost scales with the refresh interval, the work is per-paint (and the rate is
the lever). If it stays flat, something else is spinning.

Window visibility matters: Qt throttles rendering for a window that is not on
screen, which silently deflates CPU numbers. Each run is therefore focused via
hyprctl and its visibility confirmed before sampling.
"""
import os, shutil, signal, subprocess, time, glob, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exorate"

RATES = [1000, 500, 100, 33]


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
        if "qml" in cmd and "main.qml" in cmd and "exorate" in cwd:
            return int(os.path.basename(d))
    return None


def focus_exo():
    """Focus the app window so Qt actually renders it."""
    try:
        raw = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, timeout=10).stdout
        for c in json.loads(raw):
            if c.get("title") == "Exochronometer":
                subprocess.run(["hyprctl", "dispatch", "focuswindow",
                                f"address:{c['address']}"], capture_output=True, timeout=10)
                return c.get("workspace", {}).get("name"), c.get("mapped"), c.get("hidden")
    except Exception as e:
        return ("err", str(e), None)
    return (None, None, None)


base = open(os.path.join(APP, "main.qml")).read()
assert "if (page === 3) return 100" in base

for ms in RATES:
    if os.path.exists(TMP):
        shutil.rmtree(TMP)
    shutil.copytree(APP, TMP)
    body = base.replace("if (page === 3) return 100", f"if (page === 3) return {ms}", 1)
    body = body.replace("property int page: 0", "property int page: 3", 1)
    body = body.replace("""        visible: root.page === 3
        live: root.page === 3""",
                        """        visible: root.page === 3
        live: root.page === 3
        mode: 0""", 1)
    open(os.path.join(TMP, "main.qml"), "w").write(body)

    p = subprocess.Popen(["qml6", "main.qml"], cwd=TMP,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5.0)
    ws, mapped, hidden = focus_exo()
    time.sleep(1.0)
    pid = find_pid()
    if not pid:
        print(f"interval {ms:5}ms  FAILED TO START")
        p.kill(); p.wait(); continue
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(6.0)
    t1 = ticks(pid); w1 = time.time()
    cpu = (t1 - t0) / hz / (w1 - w0) * 100.0
    rate = 1000.0 / ms
    print(f"interval {ms:5}ms ({rate:5.1f} Hz)  cpu {cpu:6.1f}%   ws={ws} mapped={mapped} hidden={hidden}")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    time.sleep(1.0)

shutil.rmtree(TMP, ignore_errors=True)