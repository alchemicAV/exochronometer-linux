import QtQuick
import Quickshell
import Quickshell.Io

import ExoAudio 1.0

// Plays the app's real-time module from inside QUICKSHELL, which is the host the
// toolbar panel runs in - not the same thing as the standalone app working.
//
// Used with scripts/capture-while.sh to record the device while this plays, so the
// panel's audio path is verified the same way the app's was: at the output, not
// from a counter. The file it writes is read back as the run's own evidence of
// what the engine reported.
ShellRoot {
    id: root

    RealtimeAudio {
        id: engine

        tones: [
            { frequency: 110.0, amplitude: 0.5 },
            { frequency: 220.0, amplitude: 0.4 },
            { frequency: 330.0, amplitude: 0.35 },
        ]
        shape: ({
            attackMs: 150, releaseMs: 800, lowpassHz: 2700,
            reverbMix: 40, reverbPreset: 4,
            tremoloRateHz: 0, tremoloDepth: 0, width: 0.35,
            unisonVoices: 2, detuneCents: 2.2,
            enrichment: 0.8, partials: 3, partialTilt: 0,
        })

        Component.onCompleted: start()
    }

    FileView {
        id: out
        path: "/tmp/quickshell-rt-report.txt"
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            out.setText("QS " + engine.status + " | " + engine.detail)
            out.writeAdapter()
        }
    }
}
