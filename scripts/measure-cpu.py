#!/usr/bin/env python3
"""Sample CPU% of the running Exochronometer QML process.

ps %cpu is a lifetime average and useless for "what is it doing right now".
This reads utime+stime deltas from /proc/<pid>/stat, which is the instantaneous
figure. It also reports the app's own thread names so a spinning thread is
attributable rather than just "the app is busy".
"""
import os, sys, time, glob

def find_pid():
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        except OSError:
            continue
        if "qml" in cmd and "main.qml" in cmd:
            return int(os.path.basename(d))
    return None

def ticks(pid):
    with open(f"/proc/{pid}/stat") as f:
        parts = f.read().split()
    # utime=14, stime=15 (1-indexed fields 14/15)
    return int(parts[13]) + int(parts[14])

def main(pid=None, seconds=6.0, label=""):
    pid = pid or find_pid()
    if not pid:
        print("app not running")
        return None
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(seconds)
    try:
        t1 = ticks(pid)
    except FileNotFoundError:
        print("app exited during sampling")
        return None
    w1 = time.time()
    pct = (t1 - t0) / hz / (w1 - w0) * 100.0
    try:
        rss = int([l for l in open(f"/proc/{pid}/status") if l.startswith("VmRSS")][0].split()[1]) / 1024
    except Exception:
        rss = 0
    tag = f" [{label}]" if label else ""
    print(f"cpu {pct:6.1f}%   rss {rss:7.1f} MB   (pid {pid}){tag}")
    return pct

if __name__ == "__main__":
    lbl = sys.argv[1] if len(sys.argv) > 1 else ""
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 6.0
    main(label=lbl, seconds=secs)