import QtQuick

// Port of ColorMappingView in MiscPage.swift - amplitude-weighted HarmonicColor
// blend as swatches: one composite, then one per timeframe.
import "core/harmonicAnalysis.mjs" as HA
import "core/harmonicColor.mjs" as HC

Item {
    id: colorPage

    property var snapshot: null

    // False unless this view is the one on screen. Gates every repaint and
    // derived binding, so hidden views cost nothing.
    property bool live: true
    property bool fundamentalsOff: true
    property var excluded: []

    readonly property int scaling: 23
    readonly property var timeframeOrder: ["hour", "day", "quarterMoon", "moon", "year"]

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

    function groupOf(tones, tf) {
        const out = []
        for (let i = 0; i < tones.length; i++) if (tones[i].timeframe === tf) out.push(tones[i])
        return out
    }

    function timeframeLabel(tf) {
        if (tf === "year") return "YEAR"
        if (tf === "moon") return "MOON CYCLE"
        if (tf === "quarterMoon") return "1/4 MOON"
        if (tf === "day") return "ONE DAY"
        if (tf === "hour") return "ONE HOUR"
        return "ONE MINUTE"
    }

    readonly property var tones: {
        // Gate the tone scan: hidden views compute nothing.
        if (!colorPage.live) return []
        const snap = colorPage.snapshot
        return snap ? filteredTones(new Date(snap.timestamp)) : []
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: parent.width
            spacing: 10

            // COMPOSITE
            Column {
                width: col.width
                spacing: 4
                Row {
                    width: parent.width
                    Text {
                        text: "COMPOSITE"
                        color: Qt.rgba(1,1,1,0.55)
                        font.family: "monospace"; font.pixelSize: 9; font.letterSpacing: 2
                    }
                    Item { width: parent.width - 120; height: 1 }
                    Text {
                        text: String(colorPage.tones.length)
                        color: Qt.rgba(1,1,1,0.4)
                        font.family: "monospace"; font.pixelSize: 8
                    }
                }
                Rectangle {
                    width: col.width
                    height: 90
                    radius: 4
                    color: {
                        const c = HC.blendedColor(colorPage.tones)
                        return Qt.rgba(c.r, c.g, c.b, 1)
                    }
                    border.color: Qt.rgba(1,1,1,0.18)
                    border.width: 0.5
                }
            }

            Text {
                text: "PER TIMEFRAME"
                color: Qt.rgba(1,1,1,0.4)
                font.family: "monospace"; font.pixelSize: 8; font.letterSpacing: 2
            }

            Repeater {
                model: colorPage.timeframeOrder.length

                delegate: Column {
                    required property int index
                    readonly property string tf: colorPage.timeframeOrder[index]
                    readonly property var grp: colorPage.groupOf(colorPage.tones, tf)

                    width: col.width
                    spacing: 4

                    Row {
                        width: parent.width
                        Text {
                            text: colorPage.timeframeLabel(parent.parent.tf)
                            color: Qt.rgba(1,1,1,0.55)
                            font.family: "monospace"; font.pixelSize: 9; font.letterSpacing: 2
                        }
                        Item { width: parent.width - 120; height: 1 }
                        Text {
                            text: String(parent.parent.grp.length)
                            color: Qt.rgba(1,1,1,0.4)
                            font.family: "monospace"; font.pixelSize: 8
                        }
                    }
                    Rectangle {
                        width: col.width
                        height: 36
                        radius: 4
                        color: {
                            const c = HC.blendedColor(parent.grp)
                            return Qt.rgba(c.r, c.g, c.b, 1)
                        }
                        border.color: Qt.rgba(1,1,1,0.18)
                        border.width: 0.5
                    }
                }
            }
        }
    }
}