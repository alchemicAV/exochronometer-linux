import QtQuick
import "core/theme.mjs" as Theme

// Port of MiscPage.swift - the mode shell. MiscMode.allCases order is
// preserved exactly:
//
//   0 PHASE  1 CENTS  2 DISSONANCE  3 CHLADNI  4 SPECTROGRAM
//   5 CHORDS  6 COLOR  7 LISSAJOUS  8 SELECTOR  9 GEOMETRY
//
// GEOMETRY is the ported GeometryHarmonicsPage, which used to be page 2 of the
// tab bar. Moved here so the bar is five pages; the view itself is unchanged.
//
// The hour/day/qtr/moon/year filter applies everywhere except COLOR and CHORDS,
// matching the original's showsTimeframeRow.
Item {
    id: misc

    property var snapshot: null
    property bool fundamentalsOff: true
    property int mode: 0
    property var excluded: []

    // Set by the page host: false unless MISC is the visible page. Every mode
    // view ANDs this with its own mode test, so only the displayed mode computes.
    property bool live: true

    readonly property var filterTimeframes: ["hour", "day", "quarterMoon", "moon", "year"]
    readonly property int scaling: 23

    readonly property var modeLabels:
        ["PHASE", "CENTS", "DISSONANCE", "CHLADNI", "SPECTROGRAM",
         "CHORDS", "COLOR", "LISSAJOUS", "SELECTOR", "GEOMETRY"]

    readonly property var modeSubtitles: [
        "signal vs derivative \u00B7 closed orbits = periodic",
        "Just Intonation  \u00B7  A4 = 432 Hz",
        "Tenney height + Shannon entropy of JI guesses",
        "2D membrane modes summed by amplitude",
        "linear \u00B7 quarter-moon window \u00B7 refreshes every 10s",
        "time until next angular alignment (live)",
        "pitch class mapped to closed color wheel via magenta",
        "within-timeframe pairs \u00B7 sectioned fast \u2192 slow",
        "all timeframes merged on (divisions \u00D7 degrees)",
        "every shape's polygon, ratio, period and named interval"
    ]

    function showsTimeframeRow() {
        // COLOR and CHORDS have no timeframe filter in the original, and
        // GEOMETRY carries its own selector.
        return mode !== 6 && mode !== 5 && mode !== 9
    }

    function isExcluded(tf) { return excluded.indexOf(tf) >= 0 }

    function toggleExcluded(tf) {
        const out = []
        for (let i = 0; i < excluded.length; i++) if (excluded[i] !== tf) out.push(excluded[i])
        if (out.length === excluded.length) out.push(tf)
        excluded = out
    }

    Column {
        id: top

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        // ── header ──
        Column {
            width: top.width
            spacing: 4
            Text {
                text: "MISC ANALYSIS"
                color: Theme.fg(0.6)
                font.family: "monospace"
                font.pixelSize: 10
                font.letterSpacing: 3
            }
            Text {
                text: misc.modeSubtitles[misc.mode]
                color: Theme.fg(0.35)
                font.family: "monospace"
                font.pixelSize: 9
            }
        }

        // ── mode picker (nine chips do not fit a narrow window) ──
        Flickable {
            width: top.width
            height: 22
            contentWidth: modeRow.width
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            Row {
                id: modeRow
                spacing: 6

                Repeater {
                    model: misc.modeLabels.length
                    delegate: Rectangle {
                        required property int index
                        readonly property bool sel: misc.mode === index
                        width: modeLabel.width + 20
                        height: 22
                        radius: 11
                        color: sel ? Theme.accent() : "transparent"
                        border.color: sel ? "transparent" : Theme.fg(0.25)
                        border.width: 0.5
                        Text {
                            id: modeLabel
                            anchors.centerIn: parent
                            text: misc.modeLabels[parent.index]
                            color: parent.sel ? Theme.onAccent() : Theme.fg(0.7)
                            font.family: "monospace"
                            font.pixelSize: 8
                            font.letterSpacing: 2
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: misc.mode = parent.index
                        }
                    }
                }
            }
        }

        // ── timeframe filter ──
        Row {
            spacing: 6
            visible: misc.showsTimeframeRow()

            Repeater {
                model: misc.filterTimeframes.length
                delegate: Rectangle {
                    required property int index
                    readonly property string tf: misc.filterTimeframes[index]
                    readonly property bool ex: misc.isExcluded(tf)
                    width: chipLabel.width + 16
                    height: 22
                    radius: 11
                    color: "transparent"
                    border.color: ex ? Theme.fg(0.12) : Theme.fg(0.4)
                    border.width: 0.5
                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: parent.tf === "quarterMoon" ? "QTR" : parent.tf.toUpperCase()
                        color: Theme.fg(parent.ex ? 0.25 : 0.8)
                        font.family: "monospace"
                        font.pixelSize: 8
                        font.letterSpacing: 2
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: misc.toggleExcluded(parent.tf)
                    }
                }
            }
        }
    }

    // ── mode content ──
    Item {
        id: contentArea
        anchors.top: top.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        PhasePortraitView {
            anchors.fill: parent
            visible: misc.mode === 0
            live: misc.live && misc.mode === 0
            snapshot: misc.snapshot
            fundamentalsOff: misc.fundamentalsOff
            excluded: misc.excluded
        }

        CentsWheelView {
            anchors.fill: parent
            visible: misc.mode === 1
            live: misc.live && misc.mode === 1
            snapshot: misc.snapshot
            fundamentalsOff: misc.fundamentalsOff
            excluded: misc.excluded
        }

        DissonanceMeters {
            anchors.fill: parent
            visible: misc.mode === 2
            live: misc.live && misc.mode === 2
            snapshot: misc.snapshot
            fundamentalsOff: misc.fundamentalsOff
            excluded: misc.excluded
        }

        ChladniView {
            anchors.fill: parent
            visible: misc.mode === 3
            live: misc.live && misc.mode === 3
            snapshot: misc.snapshot
            fundamentalsOff: misc.fundamentalsOff
            excluded: misc.excluded
        }

        SpectrogramView {
            anchors.fill: parent
            visible: misc.mode === 4
            live: misc.live && misc.mode === 4
            snapshot: misc.snapshot
            fundamentalsOff: misc.fundamentalsOff
            excluded: misc.excluded
        }

        ConvergenceView {
            id: convergence
            anchors.fill: parent
            visible: misc.mode === 5
            live: misc.live && misc.mode === 5
            fundamentalsOff: misc.fundamentalsOff
        }

        ColorMappingView {
            anchors.fill: parent
            visible: misc.mode === 6
            live: misc.live && misc.mode === 6
            snapshot: misc.snapshot
            fundamentalsOff: misc.fundamentalsOff
            excluded: misc.excluded
        }

        LissajousView {
            anchors.fill: parent
            visible: misc.mode === 7
            live: misc.live && misc.mode === 7
            snapshot: misc.snapshot
            excluded: misc.excluded
        }

        SelectorView {
            anchors.fill: parent
            visible: misc.mode === 8
            live: misc.live && misc.mode === 8
            snapshot: misc.snapshot
            excluded: misc.excluded
        }

        GeometryHarmonicsView {
            anchors.fill: parent
            visible: misc.mode === 9
            live: misc.live && misc.mode === 9
            snapshot: misc.snapshot
        }
    }
}