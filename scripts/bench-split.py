#!/usr/bin/env python3
"""Split the app's CPU into "build the snapshot" vs "react to the snapshot".

`frozen` (no snapshot change at all) already measured 0.3%, so essentially all
of the ~101% is the 15 Hz refresh. But that could be either:
  (a) Exo.capture() itself -- rebuilding the snapshot each tick, or
  (b) every view's bindings/handlers re-evaluating because `snapshot` changed.

Each variant is a throwaway copy of the app directory, patched and run in
isolation so the real build is never touched.

  base        - as shipped
  capture     - 15 Hz timer still calls Exo.capture(), but result is discarded,
                so no property changes and nothing can react  -> (a) alone
  connoff     - snapshot still assigned, but every Canvas repaint handler is
                disabled via Connections.enabled = false
"""
import os, re, shutil, signal, subprocess, time, glob

SRC_APP = os.path.expanduser("~/exochronometer-linux/build/app")
TMP = "/tmp/exobench"

REFRESH = """    function refresh() {
        snapshot = Exo.capture(new Date())
    }"""
assert REFRESH in open(os.path.join(SRC_APP, "main.qml")).read()

VARIANTS = {
    "base": {},
    "capture": {"main.qml": [(REFRESH, """    function refresh() {
        Exo.capture(new Date())
    }""")]},
    "connoff": {".*": "connections"},
}


def ticks(pid):
    p = open(f"/proc/{pid}/stat").read().split()
    return int(p[13]) + int(p[14])


def find_pid(marker):
    """Find a qml6 process by its cwd (cmdline does not carry the directory)."""
    for d in glob.glob("/proc/[0-9]*"):
        try:
            cmd = open(os.path.join(d, "cmdline"), "rb").read().decode(errors="replace")
            cwd = os.readlink(os.path.join(d, "cwd"))
        except OSError:
            continue
        if "qml" in cmd and "main.qml" in cmd and marker in cwd:
            return int(os.path.basename(d))
    return None


def build(name, spec):
    d = os.path.join(TMP, name)
    if os.path.exists(d):
        shutil.rmtree(d)
    shutil.copytree(SRC_APP, d)
    for fname, patch in spec.items():
        if patch == "connections":
            for q in glob.glob(os.path.join(d, "*.qml")):
                t = open(q).read()
                t2 = re.sub(r"Connections\s*\{", "Connections {\n enabled: false", t)
                if t2 != t:
                    open(q, "w").write(t2)
        else:
            for old, new in patch:
                q = os.path.join(d, fname)
                t = open(q).read()
                assert old in t, f"patch target missing in {fname}"
                open(q, "w").write(t.replace(old, new, 1))
    return d


for name, spec in VARIANTS.items():
    d = build(name, spec)
    p = subprocess.Popen(["qml6", "main.qml"], cwd=d,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(4.5)
    pid = find_pid(f"exobench/{name}")
    if not pid:
        print(f"{name:9s} FAILED TO START")
        p.kill(); p.wait(); continue
    hz = os.sysconf("SC_CLK_TCK")
    t0 = ticks(pid); w0 = time.time()
    time.sleep(6.0)
    t1 = ticks(pid); w1 = time.time()
    print(f"{name:9s} cpu {(t1 - t0) / hz / (w1 - w0) * 100.0:6.1f}%")
    p.send_signal(signal.SIGTERM)
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill(); p.wait()
    shutil.rmtree(d, ignore_errors=True)
    time.sleep(1.0)