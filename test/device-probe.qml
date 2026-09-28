import QtQuick
import QtQuick.Window
import ExoAudio 1.0

// Plays through the real-time module so its output can be recorded and checked.
// Deliberately uses the module's DEFAULTS for the output format, because the bug
// this guards against lived in the format conversion: the device's preferred
// format here is Int32, and writing Int16 into it halved the effective rate.
Window {
    id: root
    width: 320
    height: 90
    visible: true
    color: "#101014"
    title: "device-probe"

    RealtimeAudio { id: engine }

    Text {
        anchors.centerIn: parent
        color: "#ccd"
        font.family: "monospace"
        font.pixelSize: 11
        text: "device audio probe"
    }

    Component.onCompleted: {
        engine.tones = [
            { frequency: 110.0, amplitude: 0.5 },
            { frequency: 220.0, amplitude: 0.4 },
            { frequency: 330.0, amplitude: 0.35 },
        ]
        engine.shape = {
            attackMs: 150, releaseMs: 800, lowpassHz: 2700,
            reverbMix: 40, reverbPreset: 4,
            tremoloRateHz: 0, tremoloDepth: 0, width: 0.35,
            unisonVoices: 2, detuneCents: 2.2,
            enrichment: 0.8, partials: 3, partialTilt: 0,
        }
        engine.start()
    }
}
