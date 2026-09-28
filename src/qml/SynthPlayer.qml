import QtQuick
import QtMultimedia
import "core/wavRender.mjs" as WAV

// Plays the instrument's composite signal, shaped by the synth's voicing layer.
//
// `tones` is the same list the spectrum chart and the oscilloscope are built
// from; `shape` is the SPECTRUM page's SynthParams. WAV renders exactly that sum
// through the voicing chain (unison detune, partials, width, tremolo, low-pass,
// reverb) into a 16-bit PCM WAV handed to MediaPlayer as a data: URL - no
// filesystem, no new dependency, no C++.
//
// It lives in its own file so the QtMultimedia import is isolated: on a host
// without it, the Loader in HarmonicSpectrumPage simply has no item and the
// spectrum page is otherwise unaffected.
//
// SUSTAIN: the sound plays until stop() is called. `loops` is set to 1 on
// purpose - this backend does not honour a higher count for an in-memory
// buffer, so the repeat is done explicitly in onMediaStatusChanged. The buffer's
// tail is crossfaded into its head by the renderer, so the seam does not click.
//
// ATTACK/RELEASE are applied here, as a volume ramp, NOT baked into the buffer.
// A sustaining loop would otherwise re-swell on every pass.
Item {
    id: audio

    property var tones: []
    // SynthParams, or null for an unshaped render.
    property var shape: null
    property real seconds: 3.0
    property real targetVolume: 0.8

    // True between play() and stop(); what makes the repeat a loop rather than
    // a restart after the user already stopped.
    property bool wantPlaying: false

    // Surfaced on screen, because console.log is silent in this Qt build.
    property string status: "idle"
    property int renderMs: 0
    property int urlKb: 0
    property int channels: 1
    property int loopCount: 0

    readonly property bool playing: media.playbackState === MediaPlayer.PlayingState

    readonly property int attackMs: shape ? Math.max(0, shape.attackMs) : 0
    readonly property int releaseMs: shape ? Math.max(0, shape.releaseMs) : 0

    // Loop count is the honest signal that it is still going: it can only rise
    // if playback actually ran past the end of the buffer and restarted.
    readonly property string statusText: {
        if (status !== "playing") return status
        return loopCount > 0 ? "playing \u00B7 loop " + loopCount : "playing"
    }

    /// The same readout contract as RealtimePlayer: the page shows statusText
    /// plus detail and does not care which of the two is loaded.
    readonly property string detail: renderMs + " ms render \u00B7 " + urlKb + " kB \u00B7 " + channels + " ch"

    MediaPlayer {
        id: media
        audioOutput: AudioOutput {
            id: output
            volume: 0
        }
        loops: 1

        onErrorOccurred: function(error, errorString) {
            audio.status = "error: " + errorString
        }

        onMediaStatusChanged: function(mediaStatus) {
            if (mediaStatus !== MediaPlayer.EndOfMedia) return
            if (audio.wantPlaying) {
                // Explicit repeat: see the note about `loops` above.
                audio.loopCount++
                media.position = 0
                media.play()
            } else {
                audio.status = "idle"
            }
        }
    }

    NumberAnimation {
        id: fadeIn
        target: output
        property: "volume"
        to: audio.targetVolume
        duration: audio.attackMs
        easing.type: Easing.Linear
    }

    NumberAnimation {
        id: fadeOut
        target: output
        property: "volume"
        to: 0
        duration: audio.releaseMs
        easing.type: Easing.Linear
        onFinished: media.stop()
    }

    // The render is synchronous on the GUI thread and costs on the order of a
    // second for a shaped 3 s buffer, so it is deferred one turn: the status line
    // paints "rendering" first, and the press does not appear to have been ignored.
    Timer {
        id: defer
        interval: 1
        repeat: false
        onTriggered: audio.renderNow()
    }

    function renderNow() {
        const started = Date.now()
        const packet = WAV.wavPacket(tones, shape || WAV.dryShape, seconds)
        renderMs = Date.now() - started
        urlKb = Math.round(packet.url.length / 1024)
        channels = packet.channels

        media.source = packet.url
        wantPlaying = true
        loopCount = 0
        output.volume = 0
        media.play()
        fadeIn.restart()
        status = "playing"
    }

    function play() {
        if (!tones || tones.length === 0) {
            status = "nothing sounding"
            return
        }
        status = "rendering\u2026"
        defer.restart()
    }

    function stop() {
        defer.stop()
        wantPlaying = false
        if (output.volume > 0.01 && releaseMs > 0) {
            fadeOut.restart()          // let the release run, then stop
        } else {
            media.stop()
            output.volume = 0
        }
        status = "idle"
    }

    function toggle() {
        if (playing || wantPlaying) stop()
        else play()
    }
}