#!/usr/bin/env python3
"""Same directory, same content, two filenames: main.qml vs main-p3.qml.

measure-pages runs `main-p3.qml` and sees 101%; the other harnesses run
`main.qml` and see 34%. This writes BOTH files with identical content into one
directory and measures each, to decide whether the filename itself is the
variable (which would point at Qt's compiled-QML disk cache keyed by URL).
"""
import os, shutil, signal, subprocess, time, glob, json

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exoname"

if os.path.exists(TMP):
    shutil.rmtree(TMP)
shutil.copytree(APP, TMP)

src = open(os.path.join(APP, "main.qml")).read()
body = src.replace("property int page: 0", "property int page: 3", 1)
open(os.path.join(TMP, "main.qml"), "w").write(body)
open(os.path.join(TMP, "main-p3.qml"), "w").write(body)


def ticks(pid):
    p = open(f"/proc/{pid}/stat").read().split()
    return int(p[13]) + int(p[14])


def find_pid(marker):
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
        except OSError:
            continue
        if "qml" in cmd and marker in cmd:
            return int(os.path.basename(d))
    return None


def run(qmlfile):
    p = subprocess.Popen(["qml6", qmlfile], cwd=TMP,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(6)
    pid = find_pid(qmlfile)
    if not pid:
        print(f"  {qmlfile:14s} FAILED"); p.kill(); p.wait(); return
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(6)
    t1 = ticks(pid); w1 = time.time()
    print(f"  {qmlfile:14s} cpu {(t1 - t0) / hz / (w1 - w0) * 100.0:6.1f}%  (pid {pid})")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    time.sleep(1.5)


print("identical content, same dir:")
run("main.qml")
run("main-p3.qml")
run("main.qml")
run("main-p3.qml")

# Where does Qt keep compiled QML?
print("\nQML disk cache candidates:")
for c in ["~/.cache/qmlcache", "~/.cache/qt6/qmlcache", "~/.cache/QtProject"]:
    p = os.path.expanduser(c)
    print(f"  {p}: {'EXISTS' if os.path.exists(p) else '-'}")

shutil.rmtree(TMP, ignore_errors=True)