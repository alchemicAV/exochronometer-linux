import QtQuick

// Port of LissajousView / LissajousSection / LissajousCell in MiscPage.swift -
// every within-timeframe tone pair drawn as a Lissajous figure, sectioned from
// fast timeframes to slow, two cells per row.
import "core/harmonicAnalysis.mjs" as HA
import "core/geometry.mjs" as Geo

Item {
    id: liss

    property var snapshot: null

    // False unless this view is the one on screen. Gates every repaint and
    // derived binding, so hidden views cost nothing.
    property bool live: true
    property var excluded: []

    readonly property int scaling: 23
    readonly property var orderedTimeframes: ["hour", "day", "quarterMoon", "moon", "year"]

    readonly property var visibleTimeframes: {
        const out = []
        for (let i = 0; i < orderedTimeframes.length; i++) {
            if (excluded.indexOf(orderedTimeframes[i]) < 0) out.push(orderedTimeframes[i])
        }
        return out
    }

    readonly property var pairsByTF: {
        const result = {}
        // Gate the pair enumeration: hidden views compute nothing.
        if (!liss.live) return result
        const snap = liss.snapshot
        if (!snap) return result
        const tones = HA.activeTonesForScales(new Date(snap.timestamp), [scaling])
        const grouped = {}
        for (let i = 0; i < tones.length; i++) {
            const tf = tones[i].timeframe
            if (grouped[tf] === undefined) grouped[tf] = []
            grouped[tf].push(tones[i])
        }
        for (let v = 0; v < visibleTimeframes.length; v++) {
            const tf = visibleTimeframes[v]
            const group = grouped[tf] === undefined ? [] : grouped[tf]
            const pairs = []
            if (group.length >= 2) {
                for (let i = 0; i < group.length; i++) {
                    for (let j = i + 1; j < group.length; j++) {
                        pairs.push({ a: group[i], b: group[j] })
                    }
                }
            }
            result[tf] = pairs
        }
        return result
    }

    function timeframeLabel(tf) {
        if (tf === "year") return "YEAR"
        if (tf === "moon") return "MOON CYCLE"
        if (tf === "quarterMoon") return "1/4 MOON"
        if (tf === "day") return "ONE DAY"
        if (tf === "hour") return "ONE HOUR"
        return "ONE MINUTE"
    }

    /** Ratio in lowest integer terms. A winding tone's frequency is
     *  divisions/skip x fundamental, so the pair ratio is
     *  (aDiv*bSkip):(bDiv*aSkip). */
    function ratioOf(pair) {
        const a = pair.a.divisions * pair.b.skip
        const b = pair.b.divisions * pair.a.skip
        const g = Geo.gcd(a, b)
        return { m: a / g, n: b / g }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 18

            Repeater {
                model: liss.visibleTimeframes.length

                delegate: Column {
                    required property int index
                    readonly property string tf: liss.visibleTimeframes[index]
                    readonly property var pairs: liss.pairsByTF[tf] === undefined
                                                 ? [] : liss.pairsByTF[tf]

                    width: col.width
                    spacing: 8

                    Text {
                        text: liss.timeframeLabel(parent.tf)
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: "monospace"
                        font.pixelSize: 9
                        font.letterSpacing: 2
                    }

                    // LissajousSection's empty placeholder. It is the
                    // original's own behaviour -- a timeframe contributes a
                    // pair only when it has >= 2 active tones, and the moon
                    // frequently has just its fundamental. Caption added so an
                    // empty box reads as intentional rather than broken.
                    Rectangle {
                        visible: parent.pairs.length === 0
                        width: parent.width
                        height: 80
                        radius: 4
                        color: "transparent"
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 0.5

                        Text {
                            anchors.centerIn: parent
                            text: "no tone pairs active at this scale"
                            color: Qt.rgba(1, 1, 1, 0.3)
                            font.family: "monospace"
                            font.pixelSize: 9
                            font.letterSpacing: 1
                        }
                    }

                    Grid {
                        // Guarded: in a host that instantiates this tree through
                        // a Loader (the Omarchy shell panel), the Grid's model
                        // binding can be evaluated before the delegate's `pairs`
                        // exists, which threw "Cannot read property 'length' of
                        // undefined" into the shell's journal on every start.
                        visible: parent.pairs !== undefined && parent.pairs.length > 0
                        width: parent.width
                        columns: 2
                        spacing: 12
                        readonly property real cellW: (width - spacing) / 2

                        Repeater {
                            model: parent.pairs !== undefined ? parent.pairs.length : 0

                            delegate: Column {
                                required property int index
                                readonly property var pair: parent.parent.pairs[index]
                                readonly property var ratio: liss.ratioOf(pair)

                                width: parent.parent.cellW
                                spacing: 4

                                Canvas {
                                    id: cellCanvas
                                    width: parent.width
                                    height: width

                                    Connections {
                                        target: liss
                                        // Only the displayed view repaints; a
                                        // hidden Canvas still runs onPaint.
                                        function onSnapshotChanged() {
                                            if (liss.live) cellCanvas.requestPaint()
                                        }
                                        function onLiveChanged() {
                                            if (liss.live) cellCanvas.requestPaint()
                                        }
                                    }
                                    Component.onCompleted: requestPaint()

                                    onPaint: {
                                        const ctx = getContext("2d")
                                        ctx.reset()
                                        const p = parent.pair
                                        if (!p) return
                                        const r = liss.ratioOf(p)
                                        const cx = width / 2
                                        const cy = height / 2
                                        const rad = Math.min(width, height) / 2 - 4
                                        const samples = 800

                                        const amp = p.a.amplitude * p.b.amplitude
                                        const isBothFund = HA.isFundamental(p.a) && HA.isFundamental(p.b)
                                        const opacity = isBothFund ? 0.85 : (0.4 + 0.5 * amp)

                                        ctx.strokeStyle = "rgba(255,255,255," + opacity.toFixed(3) + ")"
                                        ctx.lineWidth = 0.7
                                        ctx.beginPath()
                                        for (let i = 0; i <= samples; i++) {
                                            const theta = (i / samples) * 2 * Math.PI
                                            const x = cx + Math.sin(r.m * theta) * rad
                                            const y = cy + Math.sin(r.n * theta) * rad
                                            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                                        }
                                        ctx.stroke()
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: parent.width
                                    anchors.top: parent.top
                                    radius: 4
                                    color: "transparent"
                                    border.color: Qt.rgba(1, 1, 1, 0.15)
                                    border.width: 0.5
                                    z: -1
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: parent.ratio.m + ":" + parent.ratio.n
                                    color: Qt.rgba(1, 1, 1, 0.75)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.5
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}