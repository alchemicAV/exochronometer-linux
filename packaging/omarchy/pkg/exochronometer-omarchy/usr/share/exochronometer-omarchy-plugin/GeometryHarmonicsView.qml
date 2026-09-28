import QtQuick
import "core/theme.mjs" as Theme

// Port of GeometryHarmonicsPage (GeometryHarmonicsView.swift): a timeframe
// selector, an ALL HARMONICS toggle, then one row per shape showing its polygon,
// ratio, period and named interval - or, with the toggle on, the full
// frequency/period/JI table for every timeframe.
//
// This was page 2 of the tab bar. It now runs as a MISC mode, so the top bar is
// five pages instead of six; nothing else about it changed.
import "core/geometry.mjs" as Geo
import "core/timeFrame.mjs" as TF
import "core/frequencyMath.mjs" as Freq
import "core/intervalNames.mjs" as IN
import "core/justIntonation.mjs" as JI

Item {
    id: harm

    property var snapshot: null
    // False unless MISC is showing this mode. Gates the expensive table build.
    property bool live: true

    property int harmonicsTimeframe: 3
    property bool showAllHarmonics: false

    readonly property var shapes: Geo.defaultShapes

    // ─────────────── page: geometry harmonics ─────────────────────
    // Mirrors GeometryHarmonicsPage: a timeframe selector, an ALL HARMONICS
    // toggle, then one row per shape showing its polygon, ratio, period and
    // named interval - or, with the toggle on, the full frequency/period/JI
    // table for every timeframe.
    Flickable {
        id: harmFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: harmCol.height + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: harmCol
            x: 20
            y: 0
            width: harmFlick.width - 40
            spacing: 12

            // --- timeframe selector (3-column capsule grid) ---
            Grid {
                width: parent.width
                columns: 3
                spacing: 6

                Repeater {
                    model: TF.allCases.length
                    delegate: Rectangle {
                        required property int index
                        readonly property string tf: TF.allCases[index]

                        width: (harmCol.width - 12) / 3
                        height: 26
                        radius: 13
                        color: harm.harmonicsTimeframe === index
                            ? Theme.fg(1) : "transparent"
                        border.color: Theme.fg(0.3)
                        border.width: 0.5

                        Text {
                            anchors.centerIn: parent
                            text: TF.label(parent.tf)
                            font.family: "monospace"
                            font.pixelSize: 9
                            font.letterSpacing: 2
                            color: harm.harmonicsTimeframe === index
                                ? Theme.onAccent() : Theme.fg(0.7)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: harm.harmonicsTimeframe = parent.index
                        }
                    }
                }
            }

            // --- ALL HARMONICS toggle ---
            Rectangle {
                x: harmCol.width - width
                width: allLabel.width + 24
                height: 24
                radius: 12
                color: harm.showAllHarmonics ? Theme.accent() : "transparent"
                border.color: Theme.fg(0.4)
                border.width: 0.5

                Text {
                    id: allLabel
                    anchors.centerIn: parent
                    text: "ALL HARMONICS"
                    font.family: "monospace"
                    font.pixelSize: 9
                    font.letterSpacing: 2
                    color: harm.showAllHarmonics ? Theme.onAccent() : Theme.fg(0.85)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: harm.showAllHarmonics = !harm.showAllHarmonics
                }
            }

            // --- caption (only in the ALL HARMONICS view) ---
            Text {
                visible: harm.showAllHarmonics
                color: Theme.fg(0.45)
                font.family: "monospace"
                font.pixelSize: 9
                text: "frequency \u00B7 period \u00B7 closest 5-limit JI note vs A=432 Hz"
            }

            // --- single-timeframe rows ---
            Column {
                width: parent.width
                spacing: 12
                visible: !harm.showAllHarmonics

                Repeater {
                    model: harm.shapes.length

                    delegate: Item {
                        id: hrow
                        required property int index
                        readonly property var shape: harm.shapes[index]
                        // harmonicPeriodSeconds, as in HarmonicRow
                        readonly property real period:
                            TF.cycleDuration(TF.allCases[harm.harmonicsTimeframe])
                            * shape.skip / shape.divisions

                        width: harmCol.width
                        height: 64

                        Canvas {
                            id: poly
                            x: 0
                            y: 4
                            width: 56
                            height: 56
                            property var shp: hrow.shape

                            onShpChanged: poly.requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                const s = poly.shp
                                if (!s) return

                                const c = width / 2
                                const rad = Math.min(width, height) / 2

                                ctx.beginPath()
                                ctx.arc(c, c, rad, 0, Math.PI * 2)
                                ctx.strokeStyle = "rgba(255,255,255,0.35)"
                                ctx.lineWidth = 0.6
                                ctx.stroke()

                                const pt = (i) => {
                                    const a = (i / s.divisions) * Math.PI * 2 - Math.PI / 2
                                    return { x: c + rad * Math.cos(a), y: c + rad * Math.sin(a) }
                                }
                                ctx.beginPath()
                                ctx.strokeStyle = "rgba(255,255,255,0.9)"
                                ctx.lineWidth = 1
                                for (let e = 0; e < s.path.length; e++) {
                                    const a = pt(s.path[e].from)
                                    const b = pt(s.path[e].to)
                                    ctx.moveTo(a.x, a.y)
                                    ctx.lineTo(b.x, b.y)
                                }
                                ctx.stroke()
                            }
                        }

                        Column {
                            x: 72
                            y: 4
                            spacing: 5

                            Row {
                                spacing: 10
                                Text {
                                    text: hrow.shape.divisions + ":" + hrow.shape.skip
                                    color: Theme.fg(1)
                                    font.family: "monospace"
                                    font.pixelSize: 18
                                    font.weight: Font.Medium
                                }
                                Text {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 4
                                    text: IN.shapeName(hrow.shape.divisions, hrow.shape.skip)
                                    color: Theme.fg(0.5)
                                    font.family: "monospace"
                                    font.pixelSize: 9
                                    font.letterSpacing: 2
                                }
                            }

                            Text {
                                text: "period: " + Freq.formatDuration(hrow.period)
                                color: Theme.fg(0.7)
                                font.family: "monospace"
                                font.pixelSize: 11
                            }

                            Text {
                                text: "interval: "
                                      + IN.intervalName(hrow.shape.divisions, hrow.shape.skip)
                                      + " (" + hrow.shape.divisions + ":" + hrow.shape.skip + ")"
                                color: Theme.fg(0.55)
                                font.family: "monospace"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }

            // --- ALL HARMONICS: every timeframe x every shape ---
            Column {
                width: parent.width
                spacing: 22
                visible: harm.showAllHarmonics

                Repeater {
                    model: TF.allCases.length

                    delegate: Column {
                        id: tfSection
                        required property int index
                        readonly property string tf: TF.allCases[index]
                        width: harmCol.width
                        spacing: 0

                        Row {
                            width: parent.width
                            Text {
                                text: TF.label(tfSection.tf)
                                color: Theme.fg(0.7)
                                font.family: "monospace"
                                font.pixelSize: 10
                                font.letterSpacing: 3
                            }
                            Item {
                                width: tfSection.width - TF.label(tfSection.tf).length * 8 - 120
                                height: 1
                            }
                            Text {
                                text: TF.sublabel(tfSection.tf)
                                color: Theme.fg(0.4)
                                font.family: "monospace"
                                font.pixelSize: 8
                            }
                        }

                        Repeater {
                            model: harm.shapes.length

                            delegate: Item {
                                id: arow
                                required property int index
                                readonly property var shape: harm.shapes[index]
                                readonly property real period:
                                    TF.cycleDuration(tfSection.tf) * shape.skip / shape.divisions
                                readonly property real frequency: period > 0 ? 1 / period : 0
                                readonly property var ji: JI.closestNote(frequency)
                                readonly property string cents:
                                    (ji.centsDelta >= 0 ? "+" : "")
                                    + ji.centsDelta.toFixed(1) + "\u00A2"

                                width: tfSection.width
                                height: 34

                                Text {
                                    x: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 44
                                    text: arow.shape.divisions + ":" + arow.shape.skip
                                    color: Theme.fg(1)
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }

                                Column {
                                    x: 56
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        text: Freq.format(arow.frequency)
                                        color: Theme.fg(0.85)
                                        font.family: "monospace"
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: "period: " + Freq.formatDuration(arow.period)
                                        color: Theme.fg(0.5)
                                        font.family: "monospace"
                                        font.pixelSize: 9
                                    }
                                }

                                Column {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        anchors.right: parent.right
                                        text: arow.ji.noteName
                                        color: Theme.fg(1)
                                        font.family: "monospace"
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        anchors.right: parent.right
                                        text: arow.cents
                                        color: Theme.fg(0.55)
                                        font.family: "monospace"
                                        font.pixelSize: 9
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 1
                                    anchors.bottom: parent.bottom
                                    color: Theme.fg(0.08)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
