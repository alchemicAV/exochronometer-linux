import QtQuick

// Port of SpectrogramView + SpectrogramBuffer in MiscPage.swift - a linear
// history rail: 400 frames sampled across a quarter-moon window (~7.38 days),
// dots placed by log frequency, refreshed every 10s.
//
// The Swift buffer fills 400 frames in one shot on a background task. Here the
// fill is sliced across event-loop turns for the same reason the chord scan is:
// QML's JS is single-threaded and 400 activeTones() calls would visibly stall.
import "core/harmonicAnalysis.mjs" as HA

Item {
    id: spectro

    property var snapshot: null

    // False unless this view is the one on screen. Gates every repaint and
    // derived binding, so hidden views cost nothing.
    property bool live: true
    // Repaint on arrival, and build lazily: a hidden spectrogram must not scan
    // 400 frames. One handler only -- QML rejects a duplicate signal handler.
    onLiveChanged: {
        if (!live) return
        canvas.requestPaint()
        if (frames.length === 0) startBuild()
    }
    property bool fundamentalsOff: true
    property var excluded: []

    readonly property int scaling: 23
    readonly property real minFreqHz: 0.1
    readonly property real maxFreqHz: 50000
    readonly property real windowSeconds: 637860   // quarter moon
    readonly property int sampleCount: 400

    // frames are oldest-first, each { t: ms, tones: [...] }
    property var frames: []
    property int buildIndex: 0
    property real buildNow: 0
    property var buildFrames: []
    property bool building: false

    Component.onCompleted: if (live) startBuild()

    // Refresh cadence from the original, but only while on screen.
    Timer {
        interval: 10000
        running: spectro.live
        repeat: true
        onTriggered: spectro.startBuild()
    }

    Timer {
        id: sliceTimer
        interval: 1
        running: false
        repeat: true
        onTriggered: spectro.stepBuild()
    }

    function startBuild() {
        if (building) return
        building = true
        buildNow = Date.now()
        buildIndex = 0
        buildFrames = []
        sliceTimer.start()
    }

    function stepBuild() {
        const t0 = Date.now()
        const denom = Math.max(1, sampleCount - 1)
        const step = windowSeconds / denom
        while (buildIndex < sampleCount) {
            const age = buildIndex * step
            const t = new Date(buildNow - age * 1000)
            buildFrames.push({ t: t.getTime(), tones: HA.activeTonesForScales(t, [scaling]) })
            buildIndex++
            if (Date.now() - t0 >= 10) break
        }
        if (buildIndex >= sampleCount) {
            sliceTimer.stop()
            // The original reverses so the newest frame is last.
            frames = buildFrames.slice().reverse()
            building = false
        }
    }

    function decadeLabel(v) {
        if (v >= 1000) return String(Math.round(v / 1000)) + "k"
        if (v >= 1) return String(Math.round(v))
        return String(v)
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        Connections {
            target: spectro
            // Only the displayed view repaints; a hidden Canvas still runs
            // onPaint when requestPaint() is called on it.
            function onSnapshotChanged() {
                if (spectro.live) canvas.requestPaint()
            }
        }
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!spectro.snapshot) return

            const logMin = Math.log(spectro.minFreqHz) / Math.LN10
            const logMax = Math.log(spectro.maxFreqHz) / Math.LN10
            const range = logMax - logMin
            if (!(range > 0)) return

            const nowMs = spectro.snapshot.timestamp
            const W = width, H = height
            const axisWidth = 30
            const plotX = axisWidth
            const plotWidth = W - axisWidth

            function mapY(f) {
                const frac = (Math.log(f) / Math.LN10 - logMin) / range
                return H * (1 - frac)
            }

            // frequency axis
            const marks = [0.1, 1.0, 10.0, 100.0, 1000.0, 10000.0]
            ctx.font = "7px monospace"
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            for (let i = 0; i < marks.length; i++) {
                const y = mapY(marks[i])
                ctx.fillStyle = "rgba(255,255,255,0.4)"
                ctx.fillText(spectro.decadeLabel(marks[i]), axisWidth / 2, y)
            }
            ctx.strokeStyle = "rgba(255,255,255,0.2)"
            ctx.lineWidth = 0.5
            ctx.beginPath(); ctx.moveTo(plotX, 0); ctx.lineTo(plotX, H); ctx.stroke()

            // frames
            const frames = spectro.frames
            for (let fi = 0; fi < frames.length; fi++) {
                const frame = frames[fi]
                const age = (nowMs - frame.t) / 1000
                if (age < 0 || age > spectro.windowSeconds) continue
                const xFrac = 1.0 - age / spectro.windowSeconds
                const x = plotX + xFrac * plotWidth

                const tones = frame.tones
                for (let ti = 0; ti < tones.length; ti++) {
                    const tone = tones[ti]
                    if (spectro.excluded.indexOf(tone.timeframe) >= 0) continue
                    if (tone.frequency < spectro.minFreqHz || tone.frequency > spectro.maxFreqHz) continue
                    if (spectro.fundamentalsOff && HA.isFundamental(tone)) continue
                    const y = mapY(tone.frequency)
                    const isFund = HA.isFundamental(tone)
                    const dotR = isFund ? 1.4 : 1.1
                    const alpha = isFund ? 0.5 : tone.amplitude * 0.85
                    ctx.beginPath()
                    ctx.arc(x, y, dotR, 0, Math.PI * 2)
                    ctx.fillStyle = "rgba(255,255,255," + alpha.toFixed(3) + ")"
                    ctx.fill()
                }
            }

            // now cursor
            ctx.strokeStyle = "rgba(255,255,255,0.4)"
            ctx.lineWidth = 0.5
            ctx.beginPath(); ctx.moveTo(W - 1, 0); ctx.lineTo(W - 1, H); ctx.stroke()

            // time markers
            const day = 86400
            const markers = [[0, "now"], [day, "1d"], [2*day, "2d"], [3*day, "3d"],
                             [4*day, "4d"], [5*day, "5d"], [6*day, "6d"], [7*day, "7d"]]
            ctx.textAlign = "center"
            for (let i = 0; i < markers.length; i++) {
                if (markers[i][0] > spectro.windowSeconds + 1) continue
                const xFrac = 1.0 - markers[i][0] / spectro.windowSeconds
                const x = plotX + xFrac * plotWidth
                ctx.fillStyle = "rgba(255,255,255,0.35)"
                ctx.fillText(markers[i][1], x, H - 6)
            }
            ctx.textBaseline = "alphabetic"
        }
    }
}