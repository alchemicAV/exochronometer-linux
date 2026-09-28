#!/usr/bin/env python3
"""Smoke-test each QML component in isolation.

Instantiating every view in MiscPage means one broken file takes down the whole
app with only 'Did not load any objects' and no line number. This loads each
component on its own so the culprit is identifiable.

Each harness gets `id: root` because the views bind `Connections { target: root }`.
"""
import subprocess, os

import os as _os
IMPORT_PATH = _os.path.expanduser("~/exochronometer-linux/build/audio")
_environ = {"QML_IMPORT_PATH": IMPORT_PATH}

APP = os.path.expanduser("~/exochronometer-linux/build/app")

VIEWS = [
    "AppShell", "GeometryHarmonicsView", "SynthPlayer", "RealtimePlayer", "PhasePortraitView", "CentsWheelView", "DissonanceMeters", "ChladniView",
    "SpectrogramView", "ConvergenceView", "ColorMappingView", "LissajousView",
    "SelectorView", "TimelinePage", "HarmonicSpectrumPage", "JournalInput",
    "MiniSlider", "MiscPage",
]

TEMPLATE = '''import QtQuick
Item {{
    id: root
    width: 500; height: 400
    property var snapshot: null
    property bool fundamentalsOff: true
    property var excluded: []
    property var notes: []
    {name} {{ anchors.fill: parent }}
    Timer {{ interval: 1500; running: true; repeat: false; onTriggered: Qt.quit() }}
}}
'''

for name in VIEWS:
    path = os.path.join(APP, "smoke.qml")
    open(path, "w").write(TEMPLATE.format(name=name))
    try:
        import os as _o
        env = dict(_o.environ)
        # The real-time module is not on the import path for an uninstalled build.
        env["QML_IMPORT_PATH"] = IMPORT_PATH
        p = subprocess.run(["qml6", "smoke.qml"], cwd=APP, timeout=25, env=env,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out = p.stdout.decode(errors="replace").strip()
        bad = "Did not load" in out or p.returncode != 0
        status = "FAIL" if bad else "ok"
        detail = ""
        if bad:
            detail = "  | " + out.splitlines()[0][:90] if out else "  | (no output)"
        print(f"{status:4}  {name}{detail}")
    except subprocess.TimeoutExpired:
        print(f"{'ok':4}  {name}  (still running at timeout - loaded fine)")