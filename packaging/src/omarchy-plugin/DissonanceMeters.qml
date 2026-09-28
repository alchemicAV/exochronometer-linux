import QtQuick

// The Tenney / harmonic-entropy meters - DissonanceView in MiscPage.swift,
// extracted so MiscPage itself is just the mode shell.
import "core/harmonicAnalysis.mjs" as HA
import "core/dissonanceMath.mjs" as DM
import "core/frequencyMath.mjs" as Freq

Item {
    id: meters

    property var snapshot: null

    // False unless this view is the one on screen. Gates every repaint and
    // derived binding, so hidden views cost nothing.
    property bool live: true
    property bool fundamentalsOff: true
    property var excluded: []

    readonly property int scaling: 23

    readonly property var stats: {
        // Gate the pair maths: no meters on screen, no Tenney/entropy work.
        if (!meters.live) return null
        const s = meters.snapshot
        if (!s) return null
        const now = new Date(s.timestamp)

        let tones = HA.activeTonesForScales(now, [meters.scaling])
        tones = tones.filter(function (t) {
            if (meters.excluded.indexOf(t.timeframe) >= 0) return false
            if (meters.fundamentalsOff && HA.isFundamental(t)) return false
            return true
        })

        const count = tones.length
        const pairs = Math.max(1, (count * (count - 1)) / 2)
        const tenneyTotal = DM.totalTenney(tones)
        const entropyTotal = DM.totalEntropy(tones)
        const tenneyPerPair = tenneyTotal / pairs
        const entropyPerPair = entropyTotal / pairs

        return {
            count: count,
            pairs: pairs,
            tenneyTotal: tenneyTotal,
            entropyTotal: entropyTotal,
            tenneyPerPair: tenneyPerPair,
            entropyPerPair: entropyPerPair,
            tenneyNorm: tenneyPerPair / DM.tenneyMeterMax,
            entropyNorm: entropyPerPair / DM.entropyMeterMax
        }
    }

    // percent = min(100 + cap, round(rawNormalized * 100))
    function meterPercent(norm) {
        return Math.min(100 + DM.spilloverDisplayCap, Math.round(norm * 100))
    }

    // spilloverPercent = min(cap, round((norm - 1) * 100)), with "+" when pegged
    function spilloverText(norm) {
        const raw = Math.round((norm - 1.0) * 100)
        const capped = Math.min(DM.spilloverDisplayCap, raw)
        return capped + "%" + (capped >= DM.spilloverDisplayCap ? "+" : "")
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: meterColumn.height + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: meterColumn
            width: parent.width
            spacing: 28

            // TENNEY DISSONANCE
            Column {
                width: meterColumn.width
                spacing: 8
                property var block: meters.stats
                property string mTitle: "TENNEY  DISSONANCE"
                property string unit: "TH"
                property real perPair: block ? block.tenneyPerPair : 0
                property real total: block ? block.tenneyTotal : 0
                property real norm: block ? block.tenneyNorm : 0
                property string leftLabel: "CONSONANT"
                property string rightLabel: "DISSONANT"
                property string caption: "per-pair avg of log2(n\u00B7d), amplitude-weighted"

                Row {
                    width: parent.width
                    Text {
                        text: parent.parent.mTitle
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: "monospace"; font.pixelSize: 9; font.letterSpacing: 3
                    }
                    Item { width: parent.width - 200; height: 1 }
                    Text {
                        text: meters.meterPercent(parent.parent.norm) + "%"
                        color: parent.parent.norm > 1.0
                            ? Qt.rgba(1, 0.35, 0.35, 0.9) : Qt.rgba(1, 1, 1, 0.55)
                        font.family: "monospace"; font.pixelSize: 9
                    }
                }

                Row {
                    spacing: 5
                    Text {
                        text: Freq.printfFixed(parent.parent.perPair, 3)
                        color: parent.parent.norm > 1.0
                            ? Qt.rgba(1, 0.35, 0.35, 0.9) : Qt.rgba(1, 1, 1, 0.9)
                        font.family: "monospace"; font.pixelSize: 30; font.weight: Font.Light
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        text: parent.parent.unit
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: "monospace"; font.pixelSize: 12
                    }
                }

                Text {
                    text: "\u03A3 " + Freq.printfFixed(parent.total, 2) + " " + parent.unit
                    color: "#ffffff"
                    font.family: "monospace"; font.pixelSize: 9; font.letterSpacing: 1.5
                }

                Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.15)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, parent.parent.norm))
                        height: parent.height
                        radius: 4
                        color: parent.parent.norm > 1.0
                            ? Qt.rgba(1, 0.2, 0.2, 0.85) : Qt.rgba(1, 1, 1, 0.85)
                    }
                }

                Row {
                    width: parent.width
                    Text {
                        text: parent.parent.leftLabel
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: "monospace"; font.pixelSize: 8; font.letterSpacing: 2
                    }
                    Item { width: (parent.width - 220) / 2; height: 1 }
                    Text {
                        visible: parent.parent.norm > 1.0
                        text: "SPILLOVER  +" + meters.spilloverText(parent.parent.norm)
                        color: Qt.rgba(1, 0.3, 0.3, 0.85)
                        font.family: "monospace"; font.pixelSize: 8; font.letterSpacing: 2
                    }
                    Item { width: (parent.width - 220) / 2; height: 1 }
                    Text {
                        text: parent.parent.rightLabel
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: "monospace"; font.pixelSize: 8; font.letterSpacing: 2
                    }
                }

                Text {
                    width: parent.width
                    text: parent.caption
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.family: "monospace"; font.pixelSize: 8
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // HARMONIC ENTROPY
            Column {
                width: meterColumn.width
                spacing: 8
                property var block: meters.stats
                property string mTitle: "HARMONIC  ENTROPY"
                property string unit: "HE"
                property real perPair: block ? block.entropyPerPair : 0
                property real total: block ? block.entropyTotal : 0
                property real norm: block ? block.entropyNorm : 0
                property string leftLabel: "CLEAR"
                property string rightLabel: "AMBIGUOUS"
                property string caption: "per-pair Shannon entropy of JI identity"

                Row {
                    width: parent.width
                    Text {
                        text: parent.parent.mTitle
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: "monospace"; font.pixelSize: 9; font.letterSpacing: 3
                    }
                    Item { width: parent.width - 200; height: 1 }
                    Text {
                        text: meters.meterPercent(parent.parent.norm) + "%"
                        color: parent.parent.norm > 1.0
                            ? Qt.rgba(1, 0.35, 0.35, 0.9) : Qt.rgba(1, 1, 1, 0.55)
                        font.family: "monospace"; font.pixelSize: 9
                    }
                }

                Row {
                    spacing: 5
                    Text {
                        text: Freq.printfFixed(parent.parent.perPair, 3)
                        color: parent.parent.norm > 1.0
                            ? Qt.rgba(1, 0.35, 0.35, 0.9) : Qt.rgba(1, 1, 1, 0.9)
                        font.family: "monospace"; font.pixelSize: 30; font.weight: Font.Light
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        text: parent.parent.unit
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: "monospace"; font.pixelSize: 12
                    }
                }

                Text {
                    text: "\u03A3 " + Freq.printfFixed(parent.total, 2) + " " + parent.unit
                    color: "#ffffff"
                    font.family: "monospace"; font.pixelSize: 9; font.letterSpacing: 1.5
                }

                Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.15)
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, parent.parent.norm))
                        height: parent.height
                        radius: 4
                        color: parent.parent.norm > 1.0
                            ? Qt.rgba(1, 0.2, 0.2, 0.85) : Qt.rgba(1, 1, 1, 0.85)
                    }
                }

                Row {
                    width: parent.width
                    Text {
                        text: parent.parent.leftLabel
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: "monospace"; font.pixelSize: 8; font.letterSpacing: 2
                    }
                    Item { width: (parent.width - 220) / 2; height: 1 }
                    Text {
                        visible: parent.parent.norm > 1.0
                        text: "SPILLOVER  +" + meters.spilloverText(parent.parent.norm)
                        color: Qt.rgba(1, 0.3, 0.3, 0.85)
                        font.family: "monospace"; font.pixelSize: 8; font.letterSpacing: 2
                    }
                    Item { width: (parent.width - 220) / 2; height: 1 }
                    Text {
                        text: parent.parent.rightLabel
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: "monospace"; font.pixelSize: 8; font.letterSpacing: 2
                    }
                }

                Text {
                    width: parent.width
                    text: parent.caption
                    color: Qt.rgba(1, 1, 1, 0.35)
                    font.family: "monospace"; font.pixelSize: 8
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Text {
                text: {
                    const s = meters.stats
                    if (!s) return ""
                    return s.count + " active tones \u00B7 " + s.pairs + " pairs"
                }
                color: Qt.rgba(1, 1, 1, 0.4)
                font.family: "monospace"; font.pixelSize: 9; font.letterSpacing: 1.5
            }
        }
    }
}