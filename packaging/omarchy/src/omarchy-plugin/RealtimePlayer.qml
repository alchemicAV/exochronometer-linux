import QtQuick
import ExoAudio 1.0

// Real-time synthesis through the C++ QML module.
//
// Unlike SynthPlayer.qml - which renders a buffer and hands MediaPlayer a data:
// URL - this drives a QAudioSink that pulls samples as the device needs them, so
// playback is continuous: it starts on the first sample, never loops, never ends
// on its own, and a change to the sound is heard immediately.
//
// The tone BANK still comes from the display tick, exactly as it does everywhere
// else in the port: the kernel slews each voice toward its new target, so a bank
// that moves under the music swells rather than clicking. `bankProvider` is how
// it asks for the current bank - a function the page hands in - and the timer
// below is the re-read rate.
//
// HarmonicSpectrumPage loads this first and falls back to SynthPlayer.qml if the
// module cannot be imported (a machine without it, or another architecture), so
// both hosts still make sound either way. Both files expose the same surface:
// tones, shape, play, stop, toggle, playing, statusText, detail.
Item {
    id: audio

    property var tones: []
    // SynthParams, or null for the kernel's own defaults.
    property var shape: null
    // A function returning the current bank, re-read while playing.
    property var bankProvider: null
    property int bankRefreshMs: 500

    property string status: "idle"
    property string detail: ""
    property int channels: 2
    property int loopCount: 0        // never increments: there is nothing to loop

    readonly property bool playing: engine.running
    readonly property string statusText: status

    RealtimeAudio {
        id: engine

        // Qt re-evaluates these when the page assigns them, which lands in
        // setTones()/setShape() on the C++ side.
        tones: audio.tones
        shape: audio.shape ? audio.shape : ({})

        onChanged: {
            audio.status = engine.status
            audio.detail = engine.detail
            audio.channels = engine.channels
        }
    }

    // The bank moves with the geometry; this is what makes the sound follow the
    // moment rather than the instant PLAY was pressed.
    Timer {
        interval: audio.bankRefreshMs
        running: engine.running && audio.bankProvider !== null
        repeat: true
        onTriggered: {
            if (audio.bankProvider) audio.tones = audio.bankProvider()
        }
    }

    function play() {
        if (!tones || tones.length === 0) {
            status = "nothing sounding"
            return
        }
        engine.start()
        status = engine.status
        detail = engine.detail
    }

    function stop() {
        engine.stop()
        status = engine.status
    }

    function toggle() {
        if (engine.running) stop()
        else play()
    }
}