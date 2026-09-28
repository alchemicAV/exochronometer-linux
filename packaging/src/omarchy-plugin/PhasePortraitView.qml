import QtQuick

// Port of PhasePortraitView in MiscPage.swift - plots (s(t), ds/dt) for the
// live tone set. A clean closed loop means a periodic (small-integer-ratio)
// chord; a dense filled region means quasi-periodic.
//
// STANDARD draws the whole set in one window; NORMALIZED gives each timeframe
// its own window so every curve traces a comparable number of cycles, each
// individually peak-normalized and coloured by HarmonicColor.
import "core/harmonicAnalysis.mjs" as HA
import "core/phasePortraitMath.mjs" as PPM
import "core/harmonicColor.mjs" as HC
import "core/timeFrame.mjs" as TF

Item {
    id: portrait

    property var snapshot: null

    // False unless this view is the one on screen. Gates every repaint and
    // derived binding, so hidden views cost nothing.
    property bool live: true
    onLiveChanged: if (live) canvas.requestPaint()
    property bool fundamentalsOff: true
    property var excluded: []

    property bool normalized: false

    readonly property int scaling: 23
    readonly property real dayWindowSeconds: 0.030
    readonly property var timeframeOrder: ["year", "moon", "quarterMoon", "day", "hour", "minute"]

    // Computed once per snapshot instead of once per consumer. onPaint, the
    // legend and the closure readout all need the same set, and each call to
    // filteredTones() re-runs activeTonesForScales().
    readonly property var liveTones: {
        if (!live) return []
        const snap = portrait.snapshot
        if (!snap) return []
        return filteredTones(new Date(snap.timestamp))
    }

    function filteredTones(date) {
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

    function compactTF(tf) {
        if (tf === "year") return "YR"
        if (tf === "moon") return "MN"
        if (tf === "quarterMoon") return "QM"
        if (tf === "day") return "DY"
        if (tf === "hour") return "HR"
        return "MIN"
    }

    function colOf(c) { return Qt.rgba(c.r, c.g, c.b, 1) }

    function normalizedWindowSeconds(tf) {
        return dayWindowSeconds * (TF.cycleDuration(tf) / 86400.0)
    }

    function groupByTimeframe(tones) {
        const g = {}
        for (let i = 0; i < tones.length; i++) {
            const tf = tones[i].timeframe
            if (g[tf] === undefined) g[tf] = []
            g[tf].push(tones[i])
        }
        return g
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        Connections {
            target: portrait
            // Only the displayed view repaints; a hidden Canvas still runs
            // onPaint when requestPaint() is called on it.
            function onSnapshotChanged() {
                if (portrait.live) canvas.requestPaint()
            }
        }
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const snap = portrait.snapshot
            if (!snap) return
            const tones = portrait.liveTones

            const cx = width / 2
            const cy = height / 2
            const r = Math.min(width, height) / 2 - 8

            // axes
            ctx.strokeStyle = "rgba(255,255,255,0.12)"
            ctx.lineWidth = 0.5
            ctx.beginPath()
            ctx.moveTo(cx - r, cy); ctx.lineTo(cx + r, cy)
            ctx.moveTo(cx, cy - r); ctx.lineTo(cx, cy + r)
            ctx.stroke()

            if (tones.length === 0) return

            // Kept at the original's 800: with the curve drawn as filled
            // squares (see drawCurve) sample count is no longer the cost.
            const samples = 800

            // `cap` is a runaway guard on the number of squares drawn for this
            // curve. A complete trace needs up to ~200k (STANDARD) or ~74k
            // total across curves (NORMALIZED), so the caps below never
            // truncate in practice -- truncating is what made the plot look
            // wrong, with the tail collapsing to scattered dots.
            function drawCurve(group, windowSeconds, color, lineWidth, cap) {
                const sigs = [], deriv = []
                let peakSig = 0, peakDeriv = 0
                for (let i = 0; i < samples; i++) {
                    const t = (i / samples) * windowSeconds
                    let s = 0, d = 0
                    for (let j = 0; j < group.length; j++) {
                        const tone = group[j]
                        const w = 2 * Math.PI * tone.frequency
                        s += Math.sin(w * t) * tone.amplitude
                        d += Math.cos(w * t) * tone.amplitude * w
                    }
                    sigs.push(s); deriv.push(d)
                    if (Math.abs(s) > peakSig) peakSig = Math.abs(s)
                    if (Math.abs(d) > peakDeriv) peakDeriv = Math.abs(d)
                }
                if (!(peakSig > 0) || !(peakDeriv > 0)) return
                const sScale = r / peakSig
                const dScale = r / peakDeriv
                // Filled squares stepped along the trace, NOT one long stroked
                // path. Qt rasterises Canvas paths on the CPU, and this trace is
                // a self-intersecting mesh: the single 800-point stroke costs a
                // full core (101%), one stroke per segment 32-38%, while stepped
                // squares reproduce the same line for ~22%.
                //
                // The mesh is inherent to the original's own parameters, not a
                // porting artifact: the hour tones are 14-18.6 kHz against a
                // 13.3 kHz Nyquist for 800 samples over a 30 ms window, so
                // consecutive samples jump up to 680 px and a complete trace
                // needs ~200k squares. `cap` is therefore a runaway guard set
                // well above what the trace actually needs -- NOT a normal
                // limit, since stopping early leaves the tail as scattered dots.
                ctx.fillStyle = color
                let prevX = null, prevY = null
                let left = cap
                for (let i = 0; i < samples; i++) {
                    const x = cx + sigs[i] * sScale
                    const y = cy - deriv[i] * dScale
                    if (prevX !== null && left > 0) {
                        const dx = x - prevX, dy = y - prevY
                        const span = Math.max(Math.abs(dx), Math.abs(dy))
                        const steps = Math.max(1, Math.ceil(span / 2))
                        for (let s = 1; s <= steps && left > 0; s++) {
                            ctx.fillRect(prevX + dx * (s / steps) - 1,
                                         prevY + dy * (s / steps) - 1, 2, 2)
                            left--
                        }
                    }
                    ctx.fillRect(x - 1, y - 1, 2, 2)
                    left--
                    prevX = x; prevY = y
                }
            }

            if (!portrait.normalized) {
                drawCurve(tones, portrait.dayWindowSeconds,
                          "rgba(255,255,255,0.85)", 1, 300000)
            } else {
                const g = portrait.groupByTimeframe(tones)
                for (let k = 0; k < portrait.timeframeOrder.length; k++) {
                    const tf = portrait.timeframeOrder[k]
                    const group = g[tf]
                    if (group === undefined || group.length === 0) continue
                    drawCurve(group, portrait.normalizedWindowSeconds(tf),
                              portrait.colOf(HC.blendedColor(group)), 0.9, 150000)
                }
            }
        }
    }

    // legend, top-left
    Column {
        x: 10
        y: 28
        spacing: 3
        Text { text: "plot of  ( s(t),  ds/dt )"; color: Qt.rgba(1,1,1,0.5); font.family: "monospace"; font.pixelSize: 8 }
        Text { text: "clean closed loop  \u2192  periodic chord (small-integer ratios)"; color: Qt.rgba(1,1,1,0.4); font.family: "monospace"; font.pixelSize: 8 }
        Text { text: "dense filled region  \u2192  quasi-periodic (incommensurate ratios)"; color: Qt.rgba(1,1,1,0.4); font.family: "monospace"; font.pixelSize: 8 }
        Text {
            text: portrait.fundamentalsOff ? "fundamentals filtered out (global)" : "fundamentals included"
            color: Qt.rgba(1,1,1,0.3); font.family: "monospace"; font.pixelSize: 8
        }
        Text {
            visible: portrait.normalized
            text: "per-timeframe window  \u00B7  30 ms \u00D7 cycle / 86400 s"
            color: Qt.rgba(1,1,1,0.3); font.family: "monospace"; font.pixelSize: 8
        }
    }

    // mode toggle, top-right
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 10
        width: normLabel.width + 20
        height: 24
        radius: 12
        color: portrait.normalized ? Qt.rgba(1,1,1,0.9) : "transparent"
        border.color: Qt.rgba(1,1,1,0.3)
        border.width: 0.5

        Text {
            id: normLabel
            anchors.centerIn: parent
            text: portrait.normalized ? "NORMALIZED" : "STANDARD"
            color: portrait.normalized ? "#000000" : Qt.rgba(1,1,1,0.7)
            font.family: "monospace"
            font.pixelSize: 9
            font.letterSpacing: 2
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: portrait.normalized = !portrait.normalized
        }
    }

    // closure readout, bottom-left
    Column {
        x: 10
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        spacing: 2

        Text {
            visible: !portrait.normalized
            text: {
                if (!portrait.live) return "Total: \u2014"
                const tones = portrait.liveTones
                const closed = PPM.isLoopClosed(tones, 0.030)
                return "Total: " + (closed ? "Closed" : "Open")
            }
            color: "#ffffff"
            font.family: "monospace"
            font.pixelSize: 9
            font.letterSpacing: 1
        }

        Repeater {
            model: portrait.normalized ? portrait.timeframeOrder.length : 0

            delegate: Row {
                required property int index
                spacing: 6
                readonly property string tf: portrait.timeframeOrder[index]
                readonly property var tones: portrait.liveTones
                visible: {
                    const g = portrait.groupByTimeframe(tones)
                    return g[tf] !== undefined && g[tf].length > 0
                }
                Rectangle {
                    width: 7
                    height: 7
                    radius: 3.5
                    color: {
                        const g = portrait.groupByTimeframe(parent.tones)
                        const grp = g[parent.tf]
                        if (grp === undefined) return "transparent"
                        return portrait.colOf(HC.blendedColor(grp))
                    }
                }
                Text {
                    text: {
                        const g = portrait.groupByTimeframe(parent.tones)
                        const grp = g[parent.tf]
                        if (grp === undefined) return ""
                        const closed = PPM.isLoopClosed(grp, portrait.normalizedWindowSeconds(parent.tf))
                        return portrait.compactTF(parent.tf) + (closed ? ": Closed" : ": Open")
                    }
                    color: "#ffffff"
                    font.family: "monospace"
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }
        }
    }
}