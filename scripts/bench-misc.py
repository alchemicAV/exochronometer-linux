#!/usr/bin/env python3
"""Measure CPU per Misc mode.

MISC is still at ~101% after gating the pages, so the cost is inside one of the
nine modes. Each is launched in isolation with both `page: 3` and its `mode:`
baked in.
"""
import os, shutil, signal, subprocess, time, glob

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exomisc"

MODES = {0: "PHASE", 1: "CENTS", 2: "DISSONANCE", 3: "CHLADNI", 4: "SPECTROGRAM",
         5: "CHORDS", 6: "COLOR", 7: "LISSAJOUS", 8: "SELECTOR"}


def ticks(pid):
    p = open(f"/proc/{pid}/stat").read().split()
    return int(p[13]) + int(p[14])


def find_pid(marker):
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
            cwd = os.readlink(os.path.join(d, "cwd"))
        except OSError:
            continue
        if "qml" in cmd and "main.qml" in cmd and marker in cwd:
            return int(os.path.basename(d))
    return None


src = open(os.path.join(APP, "main.qml")).read()
assert "property int page: 0" in src

d = TMP
if os.path.exists(d):
    shutil.rmtree(d)
shutil.copytree(APP, d)

results = []
for n, name in MODES.items():
    body = src.replace("property int page: 0", "property int page: 3", 1)
    # MiscPage is instantiated without an explicit mode; bake one in.
    body = body.replace("""        visible: root.page === 3
        live: root.page === 3""",
                        f"""        visible: root.page === 3
        live: root.page === 3
        mode: {n}""", 1)
    open(os.path.join(d, "main.qml"), "w").write(body)

    p = subprocess.Popen(["qml6", "main.qml"], cwd=d,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(5.0)
    pid = find_pid("exomisc")
    if not pid:
        print(f"mode {n} {name:12s} FAILED TO START")
        p.kill(); p.wait(); continue
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(6.0)
    t1 = ticks(pid); w1 = time.time()
    cpu = (t1 - t0) / hz / (w1 - w0) * 100.0
    results.append((n, name, cpu))
    print(f"mode {n} {name:12s} cpu {cpu:6.1f}%")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    time.sleep(1.0)

shutil.rmtree(d, ignore_errors=True)
if results:
    hi = max(results, key=lambda r: r[2])
    print(f"\nhottest: mode {hi[0]} {hi[1]} at {hi[2]:.1f}%")