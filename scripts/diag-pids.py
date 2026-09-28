#!/usr/bin/env python3
"""Launch page-3 exactly as measure-pages does, then enumerate EVERY process
whose cmdline mentions it.

measure-pages reports 101% for a configuration that measures 34% elsewhere. If
more than one matching process exists, find_pid() is returning the first match
and the harness may be sampling a stale process (e.g. one left over from an
earlier run, still running a pre-fix build) rather than the one just launched.
"""
import os, subprocess, time, glob, signal, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
src = open(os.path.join(APP, "main.qml")).read()
open(os.path.join(APP, "main-p3.qml"), "w").write(
    src.replace("property int page: 0", "property int page: 3", 1))

p = subprocess.Popen(["qml6", "main-p3.qml"], cwd=APP,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(6)

print("processes whose cmdline mentions main-p3.qml:")
cands = []
for d in sorted(glob.glob("/proc/[0-9]*"), key=lambda x: int(x.split("/")[-1])):
    try:
        cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
    except OSError:
        continue
    if "main-p3.qml" in cmd:
        pid = int(os.path.basename(d))
        cands.append(pid)
        try:
            st = open(f"/proc/{pid}/stat").read().split()
            ut, stt = int(st[13]), int(st[14])
            rss = int([l for l in open(f"/proc/{pid}/status")
                       if l.startswith("VmRSS")][0].split()[1]) / 1024
            start = st[21]
        except Exception as e:
            ut = stt = 0; rss = 0; start = "?"
        print(f"  pid {pid}  utime+stime={ut + stt}  rss={rss:.0f}MB  starttime={start}  cmd={cmd[:60]}")
print(f"\nlaunched pid was {p.pid}")
print(f"{len(cands)} matching process(es): {cands}")

# Sample each candidate for 4s to see who is burning CPU.
for pid in cands:
    try:
        a = open(f"/proc/{pid}/stat").read().split()
        a0 = int(a[13]) + int(a[14]); w0 = time.time()
        time.sleep(4)
        b = open(f"/proc/{pid}/stat").read().split()
        b1 = int(b[13]) + int(b[14]); w1 = time.time()
        print(f"  pid {pid}: cpu {(b1 - a0) / os.sysconf('SC_CLK_TCK') / (w1 - w0) * 100.0:.1f}%")
    except FileNotFoundError:
        print(f"  pid {pid}: gone")

subprocess.run(["pkill", "-x", "qml6"])
try:
    p.wait(timeout=5)
except Exception:
    p.kill()
os.remove(os.path.join(APP, "main-p3.qml"))