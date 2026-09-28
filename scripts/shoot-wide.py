#!/usr/bin/env python3
"""Render AppShell states in a real window, WIDE, on an empty workspace.

Why: hyprland tiles this app. Sharing a workspace with other windows leaves it
about 621x670 - narrower than it is tall - which hides every change that needs
width (the square colour field, the square selector grid, the side-by-side
spectrum/synth split) and is too small to judge the panel's layout at all.
Alone on a workspace it tiles to the full screen, which is the width the Omarchy
panel uses.

This also renders through the REAL scene graph and captures with grim, rather
than grabToImage: offscreen grabs of this app have been unreliable for the
canvases that were resized (they came back blank while the app itself drew them
correctly), and the real path is what the user actually sees.

    python3 scripts/shoot-wide.py [state ...]
"""
import json
import os
import subprocess
import sys
import time

APP = os.path.expanduser("~/exochronometer-linux/build/app")
TITLE = "state-grab"
WORKSPACE = 9

STATES = [
    ("circles",        0, "", 3.0),
    ("misc-phase",     2, 'setMode("exoMisc", 0)', 4.0),
    ("misc-color",     2, 'setMode("exoMisc", 6)', 4.0),
    ("misc-selector",  2, 'setMode("exoMisc", 8)', 5.0),
    ("misc-geometry",  2, 'setMode("exoMisc", 9)', 5.0),
    ("spectrum",       4, "", 4.0),
    ("spectrum-synth", 4, 'set("exoSpectrum", "showSynth", true)', 4.0),
    ("spectrum-audio", 4, 'set("exoSpectrum", "showSynth", true); '
                          'call("exoSpectrum", "toggleAudio")', 7.0),
]

TEMPLATE = '''import QtQuick
import QtQuick.Window

Window {{
    width: 1020
    height: 760
    visible: true
    color: "#0d0d11"
    title: "{title}"

    AppShell {{
        id: shell
        anchors.fill: parent
        allowQuit: false
        page: {page}
    }}

    function byName(item, name) {{
        if (!item) return null
        if (item.objectName === name) return item
        const kids = item.children
        for (let i = 0; i < kids.length; i++) {{
            const hit = byName(kids[i], name)
            if (hit) return hit
        }}
        return null
    }}

    function setMode(name, m) {{ const t = byName(shell, name); if (t) t.mode = m }}
    function set(name, prop, v) {{ const t = byName(shell, name); if (t) t[prop] = v }}
    function call(name, fn) {{
        const t = byName(shell, name)
        if (t && typeof t[fn] === "function") t[fn]()
    }}

    Component.onCompleted: {{ {setup} }}
}}
'''


def hypr(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def window_geometry():
    try:
        clients = json.loads(hypr("clients", "-j"))
    except ValueError:
        return None
    for c in clients:
        if c.get("title") == TITLE:
            x, y = c["at"]
            w, h = c["size"]
            return x, y, w, h
    return None


def current_workspace():
    try:
        for m in json.loads(hypr("monitors", "-j")):
            if m.get("focused"):
                return m["activeWorkspace"]["id"]
    except ValueError:
        pass
    return None


def main():
    wanted = sys.argv[1:]
    states = [s for s in STATES if not wanted or s[0] in wanted]
    if not states:
        print("no matching state; known:", ", ".join(s[0] for s in STATES))
        return 1

    origin = current_workspace()
    path = os.path.join(APP, "wide-grab.qml")
    ok = True
    try:
        for name, page, setup, wait in states:
            open(path, "w").write(TEMPLATE.format(title=TITLE, page=page, setup=setup))
            # launched straight onto the empty workspace, so it tiles full width
            hypr("dispatch", "exec",
                 f"[workspace {WORKSPACE} silent] qml6 wide-grab.qml")
            time.sleep(3.0)
            hypr("dispatch", f"workspace {WORKSPACE}")
            time.sleep(wait)

            geo = window_geometry()
            out = f"/tmp/wide-{name}.png"
            if not geo:
                print(f"{name:<16} FAIL  no window")
                ok = False
            else:
                x, y, w, h = geo
                subprocess.run(["grim", "-g", f"{x},{y} {w}x{h}", out], capture_output=True)
                size = os.path.getsize(out) if os.path.exists(out) else 0
                if size:
                    print(f"{name:<16} ok    {w}x{h} logical -> {size:>8} bytes  {out}")
                else:
                    print(f"{name:<16} FAIL  grim produced nothing")
                    ok = False
            subprocess.run(["pkill", "-x", "qml6"], capture_output=True)
            time.sleep(1.0)
    finally:
        if origin is not None:
            hypr("dispatch", f"workspace {origin}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())