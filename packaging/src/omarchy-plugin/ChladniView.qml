import QtQuick

// Port of ChladniView in MiscPage.swift - a square plate whose standing-wave
// pattern is the amplitude-weighted sum of sin(m*pi*x)*sin(n*pi*y) modes, one
// per active tone, with m set by timeframe and n by the tone's divisions.
//
// The grid is computed at a coarse pixel step (the original uses 4px) and the
// intensity is gamma-corrected by pow(intensity, 0.6).
import "core/harmonicAnalysis.mjs" as HA

Item {
    id: chladni

    property var snapshot: null

    // False unless this view is the one on screen. Gates every repaint and
    // derived binding, so hidden views cost nothing.
    property bool live: true
    onLiveChanged: if (live) canvas.requestPaint()
    property bool fundamentalsOff: true
    property var excluded: []

    readonly property int scaling: 23
    readonly property real pixelStep: 4

    function modeIndex(tf) {
        if (tf === "year") return 1
        if (tf === "moon") return 2
        if (tf === "quarterMoon") return 3
        if (tf === "day") return 4
        if (tf === "hour") return 5
        return 6
    }

    // Computed once per snapshot rather than once per paint.
    readonly property var liveTones: {
        if (!live) return []
        const snap = chladni.snapshot
        if (!snap) return []
        return plateTones(new Date(snap.timestamp))
    }

    function plateTones(date) {
        const all = HA.activeTonesForScales(date, [scaling])
        const out = []
        for (let i = 0; i < all.length; i++) {
            const t = all[i]
            if (excluded.indexOf(t.timeframe) >= 0) continue
            if (fundamentalsOff && HA.isFundamental(t)) continue
            out.push(t)
        }
        return out
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        radius: 4
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 0.5

        Canvas {
            id: canvas
            anchors.fill: parent

            Connections {
                target: chladni
                // Only the displayed view repaints; a hidden Canvas still runs
                // onPaint when requestPaint() is called on it.
                function onSnapshotChanged() {
                    if (chladni.live) canvas.requestPaint()
                }
            }
            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const snap = chladni.snapshot
                if (!snap) return
                const tones = chladni.liveTones

                const side = Math.min(width, height)
                const originX = (width - side) / 2
                const originY = (height - side) / 2
                const step = chladni.pixelStep
                const cells = Math.floor(side / step)
                if (!(cells > 0)) return

                const modes = []
                for (let i = 0; i < tones.length; i++) {
                    modes.push({
                        m: chladni.modeIndex(tones[i].timeframe),
                        n: tones[i].divisions,
                        amp: tones[i].amplitude
                    })
                }

                const grid = []
                let maxAbs = 0
                const denom = cells > 1 ? cells - 1 : 1
                for (let row = 0; row < cells; row++) {
                    const y = row / denom
                    const line = []
                    for (let col = 0; col < cells; col++) {
                        const x = col / denom
                        let u = 0
                        for (let k = 0; k < modes.length; k++) {
                            const mode = modes[k]
                            if (mode.amp < 0.01) continue
                            u += mode.amp * Math.sin(mode.m * Math.PI * x)
                                       * Math.sin(mode.n * Math.PI * y)
                        }
                        line.push(u)
                        const a = Math.abs(u)
                        if (a > maxAbs) maxAbs = a
                    }
                    grid.push(line)
                }
                if (!(maxAbs > 0)) return

                for (let row = 0; row < cells; row++) {
                    for (let col = 0; col < cells; col++) {
                        const intensity = Math.abs(grid[row][col]) / maxAbs
                        const alpha = Math.pow(intensity, 0.6) * 0.9
                        if (alpha <= 0.002) continue
                        ctx.fillStyle = "rgba(255,255,255," + alpha.toFixed(3) + ")"
                        ctx.fillRect(originX + col * step, originY + row * step, step, step)
                    }
                }
            }
        }
    }
}