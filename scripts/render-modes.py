#!/usr/bin/env python3
"""Render each Misc mode to a PNG using QML's own grabToImage.

The desktop session may be locked, in which case grim only captures the lock
overlay. grabToImage renders the scene graph's item tree into an offscreen
image, so it works regardless of what the compositor is showing.
"""
import subprocess, sys, os

APP = os.path.expanduser("~/exochronometer-linux/build/app")
MODES = [0, 1, 3, 4, 6, 7, 8]

HOOK = '''
    Timer {{
        interval: 2600; running: true; repeat: false
        onTriggered: {{
            root.contentItem.grabToImage(function (r) {{
                Qt.exit(r.saveToFile("file:///tmp/render-m{m}.png") ? 0 : 3);
            }});
        }}
    }}
}}
'''

src = open(os.path.join(APP, "main.qml")).read()
src = src.replace("property int page: 0", "property int page: 3")

for m in MODES:
    # Target the MiscPage block specifically: "snapshot: root.snapshot" also
    # appears in the HarmonicSpectrumPage instantiation, and replacing both
    # injects an unknown `mode` property there.
    anchor = src.find("id: miscPage")
    at = src.find("snapshot: root.snapshot", anchor)
    needle = "snapshot: root.snapshot"
    body = (src[:at] + needle + "\n        mode: %d" % m + src[at + len(needle):])
    if "mode: %d" % m not in body:
        print("mode %d: OVERRIDE FAILED" % m)
        continue
    body = body.rstrip()
    body = body[:body.rfind("}")] + HOOK.format(m=m)
    path = os.path.join(APP, "main-grab.qml")
    open(path, "w").write(body)
    out = "/tmp/render-m%d.png" % m
    if os.path.exists(out):
        os.remove(out)
    try:
        rc = subprocess.run(["qml6", "main-grab.qml"], cwd=APP,
                            timeout=30, stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE).returncode
    except subprocess.TimeoutExpired:
        rc = -1
    size = os.path.getsize(out) if os.path.exists(out) else 0
    print("mode %d: exit=%s  %s bytes" % (m, rc, size if size else "MISSING"))